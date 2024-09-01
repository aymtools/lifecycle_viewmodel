import 'package:an_lifecycle_cancellable/an_lifecycle_cancellable.dart';
import 'package:anlifecycle/anlifecycle.dart';
import 'package:cancellable/cancellable.dart';
import 'package:flutter/widgets.dart';

/// ViewModel基类
abstract class ViewModel {
  bool _mCleared = false;
  final Set<Cancellable> _closeables = {};

  /// 执行清理
  void onCleared() {}

  /// 添加一个自动清理的cancellable
  void addCloseable(Cancellable closeable) {
    if (_mCleared) return;
    _closeables.add(closeable);
  }
}

extension ViewModelExt on ViewModel {
  /// 添加一个自动清理的回调
  void onDispose(void Function() onDispose) {
    Cancellable cancellable = Cancellable();
    cancellable.onCancel.then((_) => onDispose());
    addCloseable(cancellable);
  }
}

extension _ViewModelClean on ViewModel {
  void clear() {
    if (_mCleared) return;
    _mCleared = true;
    for (Cancellable c in _closeables) {
      c.cancel();
    }
    _closeables.clear();
    onCleared();
  }
}

/// ViewModel的Store
class ViewModelStore {
  final Map<String, ViewModel> mMap = {};

  /// 放入一个ViewModel 如果已经存在则上一个执行清理
  void put(String key, ViewModel viewModel) {
    ViewModel? oldViewModel = mMap[key];
    mMap[key] = viewModel;
    if (oldViewModel != null) {
      oldViewModel.onCleared();
    }
  }

  /// 获取ViewModel
  ViewModel? get(String key) {
    return mMap[key];
  }

  /// 当前已存在的KEY
  Set<String> keys() {
    return Set.of(mMap.keys);
  }

  ///Clears internal storage and notifies ViewModels that they are no longer used.
  void clear() {
    for (ViewModel vm in mMap.values) {
      vm.clear();
    }
    mMap.clear();
  }
}

/// ViewModel创建器1
typedef ViewModelFactory<VM extends ViewModel> = VM Function();

/// ViewModel创建器2
typedef ViewModelFactory2<VM extends ViewModel> = VM Function(Lifecycle);

class _ViewModelDefFactories {
  static final _ViewModelDefFactories _instance = _ViewModelDefFactories();

  final Map<Type, Function> _factoryMap = {};

  void addFactory<VM extends ViewModel>(ViewModelFactory<VM> factory) =>
      _factoryMap[VM] = factory;

  void addFactory2<VM extends ViewModel>(ViewModelFactory2<VM> factory) =>
      _factoryMap[VM] = factory;
}

VM _getOrCreate<VM extends ViewModel>(
    Map<Type, Function> factoryMap, Lifecycle lifecycle) {
  late VM vm;
  Function factory = factoryMap[VM] as Function;
  if (factory is ViewModelFactory<VM>) {
    vm = factory();
  } else if (factory is ViewModelFactory2<VM>) {
    vm = factory(lifecycle);
  }
  return vm;
}

/// 用来管理如何创建ViewModel
class ViewModelProvider {
  final ViewModelStore _viewModelStore;
  final Lifecycle _lifecycle;
  final Map<Type, Function> _factoryMap = {};

  ViewModelProvider(this._viewModelStore, this._lifecycle);

  /// 使用当前的Provider获取或创建一个 ViewModel
  VM get<VM extends ViewModel>() {
    var vm = _viewModelStore.get(VM.toString());
    if (vm != null && vm is VM) return vm;

    if (_factoryMap.containsKey(VM)) {
      VM vm = _getOrCreate(_factoryMap, _lifecycle);
      _viewModelStore.put(VM.toString(), vm);
      return vm;
    }
    if (_ViewModelDefFactories._instance._factoryMap.containsKey(VM)) {
      VM vm = _getOrCreate(
          _ViewModelDefFactories._instance._factoryMap, _lifecycle);
      _viewModelStore.put(VM.toString(), vm);
      return vm;
    }
    throw 'cannot find $VM factory';
  }

  /// 添加一个创建器1
  void addFactory<VM extends ViewModel>(ViewModelFactory<VM> factory) =>
      _factoryMap[VM] = factory;

  /// 添加一个创建器2
  void addFactory2<VM extends ViewModel>(ViewModelFactory2<VM> factory) =>
      _factoryMap[VM] = factory;

  /// 添加 全局的 创建器1
  static void addDefFactory<VM extends ViewModel>(
          ViewModelFactory<VM> factory) =>
      _ViewModelDefFactories._instance.addFactory<VM>(factory);

  /// 添加 全局的 创建器2
  static void addDefFactory2<VM extends ViewModel>(
          ViewModelFactory2<VM> factory) =>
      _ViewModelDefFactories._instance.addFactory2<VM>(factory);

  static ViewModelProvider Function(LifecycleOwner)? _viewModelProviderProducer;

  /// 设置默认的viewModels的提供者
  static void viewModelProviderProducer<LO extends LifecycleOwnerStateMixin>(
      {bool Function(LO)? testLifecycleOwner}) {
    assert(_viewModelProviderProducer == null);
    _viewModelProviderProducer = (registry) {
      final owner = registry._findLifecycleOwner<LO>(test: testLifecycleOwner);
      if (owner == null) {
        throw 'cannot find $LO';
      }
      return owner.getViewModelProvider();
    };
  }

  /// 设置默认的viewModels的提供者 指定为基于路由 路由页面内唯一
  static void viewModelProviderProducerByRoute() =>
      viewModelProviderProducer<LifecycleRouteOwnerState>();

  /// 设置默认的viewModels的提供者 基于App app内唯一
  static void viewModelProviderProducerByApp() =>
      viewModelProviderProducer<LifecycleAppOwnerState>(
          testLifecycleOwner: (owner) => owner.lifecycle.parent == null);
}

extension ViewModelProviderViewModelsExt on ViewModelProvider {
  /// 扩展的get 可提供临时的 ViewModelFactory
  VM viewModels<VM extends ViewModel>(
      {ViewModelFactory<VM>? factory, ViewModelFactory2<VM>? factory2}) {
    if (factory != null) {
      addFactory(factory);
    }
    if (factory2 != null) {
      addFactory2(factory2);
    }
    return get<VM>();
  }
}

extension ViewModelStoreOwnerExtension on LifecycleOwner {
  /// 获取 当前的viewModelStore
  ViewModelStore getViewModelStore() =>
      lifecycleExtData.putIfAbsent(TypedKey<ViewModelStore>(), () {
        final store = ViewModelStore();
        makeLiveCancellable().onCancel.then((_) => store.clear());
        return store;
      });

  /// 获取当前的 viewModelProvider
  ViewModelProvider getViewModelProvider() {
    assert(currentLifecycleState > LifecycleState.destroyed,
        'Must be used before destroyed.');
    return lifecycleExtData.putIfAbsent(TypedKey<ViewModelProvider>(),
        () => ViewModelProvider(getViewModelStore(), lifecycle));
  }

  /// 查找最近的路由page 级别的 viewModelProvider
  ViewModelProvider getViewModelProviderByRoute() =>
      findViewModelProvider<LifecycleRouteOwnerState>();

  /// 查找最近的App 级别的 viewModelProvider
  ViewModelProvider getViewModelProviderByApp() =>
      findViewModelProvider<LifecycleAppOwnerState>(
          testLifecycleOwner: (owner) => owner.lifecycle.parent == null);

  /// 自定义查找模式 的 viewModelProvider
  ViewModelProvider findViewModelProvider<LO extends LifecycleOwnerStateMixin>(
          {bool Function(LO)? testLifecycleOwner}) =>
      _getViewModelProvider<LO>(testLifecycleOwner: testLifecycleOwner);
}

extension _ViewModelRegistryExtension on ILifecycleRegistry {
  ViewModelProvider _getViewModelProvider<LO extends LifecycleOwnerStateMixin>(
      {bool Function(LO)? testLifecycleOwner}) {
    final owner = _findLifecycleOwner<LO>(test: testLifecycleOwner);
    if (owner == null) {
      throw 'cannot find $LO';
    }
    return owner.getViewModelProvider();
  }

  LO? _findLifecycleOwner<LO extends LifecycleOwnerStateMixin>(
      {bool Function(LO)? test}) {
    Lifecycle? life = lifecycle;
    if (test == null) {
      while (life != null) {
        if (life.owner is LO) {
          return (life.owner as LO);
        }
        life = life.parent;
      }
      return null;
    }
    while (life != null) {
      if (life.owner is LO && test((life.owner as LO))) {
        return (life.owner as LO);
      }
      life = life.parent;
    }
    return null;
  }
}

extension ViewModelLifecycleExtension on ILifecycle {
  /// 获取当前环境下配置下的ViewModel
  VM viewModels<VM extends ViewModel>(
      {ViewModelFactory<VM>? factory,
      ViewModelFactory2<VM>? factory2,
      ViewModelProvider Function(LifecycleOwner lifecycleOwner)?
          viewModelProvider}) {
    final ILifecycleRegistry registry = toLifecycleRegistry();
    final owner = registry._findLifecycleOwner();
    if (owner == null) {
      throw 'cannot find LifecycleOwner';
    }

    viewModelProvider ??= ViewModelProvider._viewModelProviderProducer;
    viewModelProvider ??= (owner) => owner.getViewModelProvider();

    return viewModelProvider
        .call(owner)
        .viewModels(factory: factory, factory2: factory2);
  }

  /// 获取基于RoutePage的ViewModel
  VM viewModelsByRoute<VM extends ViewModel>({
    ViewModelFactory<VM>? factory,
    ViewModelFactory2<VM>? factory2,
  }) =>
      viewModels(
          factory: factory,
          factory2: factory2,
          viewModelProvider: (owner) => owner.getViewModelProviderByRoute());

  /// 获取基于App的ViewModel
  VM viewModelsByApp<VM extends ViewModel>({
    ViewModelFactory<VM>? factory,
    ViewModelFactory2<VM>? factory2,
  }) =>
      viewModels(
          factory: factory,
          factory2: factory2,
          viewModelProvider: (owner) => owner.getViewModelProviderByApp());

  /// 自定义按需查找的 ViewModel
  VM viewModelsByLifecycleOwner<VM extends ViewModel,
              LO extends LifecycleOwnerStateMixin>(
          {ViewModelFactory<VM>? factory,
          ViewModelFactory2<VM>? factory2,
          bool Function(LO)? testLifecycleOwner}) =>
      viewModels(
          factory: factory,
          factory2: factory2,
          viewModelProvider: (owner) => owner.findViewModelProvider<LO>(
              testLifecycleOwner: testLifecycleOwner));
}

extension ViewModelsState<T extends StatefulWidget> on State<T> {
  /// 获取最近的指定的 viewModelProvider 可提供的 ViewModel
  VM viewModelsOfState<VM extends ViewModel>(
      {ViewModelFactory<VM>? factory,
      ViewModelFactory2<VM>? factory2,
      ViewModelProvider Function(LifecycleOwner lifecycleOwner)?
          viewModelProvider}) {
    if (this is ILifecycleRegistry) {
      return (this as ILifecycleRegistry).viewModels(
          factory: factory,
          factory2: factory2,
          viewModelProvider: viewModelProvider);
    }
    assert(mounted);

    Lifecycle? lifecycle;

    assert(() {
      /// 抑制掉 assert 时的异常
      try {
        lifecycle = Lifecycle.of(context);
      } catch (_) {
        lifecycle = Lifecycle.of(context, listen: false);
      }
      return true;
    }());

    lifecycle ??= Lifecycle.of(context);
    return lifecycle!.viewModels(
        factory: factory,
        factory2: factory2,
        viewModelProvider: viewModelProvider);
  }

  /// 获取最近的Route提供的 viewModelProvider 来获取 ViewModel
  VM viewModelsByRouteOfState<VM extends ViewModel>(
          {ViewModelFactory<VM>? factory, ViewModelFactory2<VM>? factory2}) =>
      viewModelsOfState(
          factory: factory,
          factory2: factory2,
          viewModelProvider: (owner) => owner.getViewModelProviderByRoute());

  /// 获取基于App的ViewModel
  VM viewModelsByAppOfState<VM extends ViewModel>(
          {ViewModelFactory<VM>? factory, ViewModelFactory2<VM>? factory2}) =>
      viewModelsOfState(
          factory: factory,
          factory2: factory2,
          viewModelProvider: (owner) => owner.getViewModelProviderByApp());
}
