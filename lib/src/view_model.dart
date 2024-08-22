import 'package:an_lifecycle_cancellable/an_lifecycle_cancellable.dart';
import 'package:anlifecycle/anlifecycle.dart';
import 'package:cancellable/cancellable.dart';

abstract class ViewModel {
  bool _mCleared = false;
  final Set<Cancellable> _closeables = {};

  void onCleared() {}

  void addCloseable(Cancellable closeable) {
    if (_mCleared) return;
    _closeables.add(closeable);
  }
}

extension ViewModelExt on ViewModel {
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

// class _ViewModels<T>{
//   final T instanc;
//   final Set<Cancellable> _closeables = {};
//   bool _mCleared = false;
// }

class ViewModelStore {
  final Map<String, ViewModel> mMap = {};

  void put(String key, ViewModel viewModel) {
    ViewModel? oldViewModel = mMap[key];
    mMap[key] = viewModel;
    if (oldViewModel != null) {
      oldViewModel.onCleared();
    }
  }

  ViewModel? get(String key) {
    return mMap[key];
  }

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

typedef ViewModelFactory<VM extends ViewModel> = VM Function();
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

class ViewModelProvider {
  final ViewModelStore _viewModelStore;
  final Lifecycle _lifecycle;
  final Map<Type, Function> _factoryMap = {};

  ViewModelProvider(this._viewModelStore, this._lifecycle);

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

  void addFactory<VM extends ViewModel>(ViewModelFactory<VM> factory) =>
      _factoryMap[VM] = factory;

  void addFactory2<VM extends ViewModel>(ViewModelFactory2<VM> factory) =>
      _factoryMap[VM] = factory;

  static void addDefFactory<VM extends ViewModel>(
          ViewModelFactory<VM> factory) =>
      _ViewModelDefFactories._instance.addFactory<VM>(factory);

  static void addDefFactory2<VM extends ViewModel>(
          ViewModelFactory2<VM> factory) =>
      _ViewModelDefFactories._instance.addFactory2<VM>(factory);

  static ViewModelProvider Function(ILifecycleRegistry)?
      _viewModelProviderProducer;

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

  static void viewModelProviderProducerByRoute() =>
      viewModelProviderProducer<LifecycleRouteOwnerState>();

  static void viewModelProviderProducerByApp() =>
      viewModelProviderProducer<LifecycleAppOwnerState>(
          testLifecycleOwner: (owner) => owner.lifecycle.parent == null);
}

extension ViewModelStoreOwnerExtension on LifecycleOwner {
  ViewModelStore getViewModelStore() =>
      lifecycleExtData.putIfAbsent(TypedKey<ViewModelStore>(), () {
        final store = ViewModelStore();
        makeLiveCancellable().onCancel.then((_) => store.clear());
        return store;
      });

  ViewModelProvider getViewModelProvider() {
    assert(currentLifecycleState > LifecycleState.destroyed,
        'Must be used before destroyed.');
    return lifecycleExtData.putIfAbsent(TypedKey<ViewModelProvider>(),
        () => ViewModelProvider(getViewModelStore(), lifecycle));
  }

  ViewModelProvider getViewModelProviderByRoute() =>
      findViewModelProvider<LifecycleRouteOwnerState>();

  ViewModelProvider getViewModelProviderByApp() =>
      findViewModelProvider<LifecycleAppOwnerState>(
          testLifecycleOwner: (owner) => owner.lifecycle.parent == null);

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
  T viewModels<T extends ViewModel>(
      {ViewModelFactory<T>? factory, ViewModelFactory2<T>? factory2}) {
    final ILifecycleRegistry registry = toLifecycleRegistry();

    final provider = ViewModelProvider._viewModelProviderProducer == null
        ? registry._getViewModelProvider()
        : ViewModelProvider._viewModelProviderProducer!.call(registry);
    if (factory != null) {
      provider.addFactory(factory);
    }
    if (factory2 != null) {
      provider.addFactory2(factory2);
    }
    return provider.get<T>();
  }

  T viewModelsByRoute<T extends ViewModel>({
    ViewModelFactory<T>? factory,
    ViewModelFactory2<T>? factory2,
  }) =>
      viewModelsByLifecycleOwner<T, LifecycleRouteOwnerState>(
          factory: factory, factory2: factory2);

  T viewModelsByApp<T extends ViewModel>({
    ViewModelFactory<T>? factory,
    ViewModelFactory2<T>? factory2,
  }) =>
      viewModelsByLifecycleOwner<T, LifecycleAppOwnerState>(
          factory: factory,
          factory2: factory2,
          testLifecycleOwner: (owner) => owner.lifecycle.parent == null);

  T viewModelsByLifecycleOwner<T extends ViewModel,
          LO extends LifecycleOwnerStateMixin>(
      {ViewModelFactory<T>? factory,
      ViewModelFactory2<T>? factory2,
      bool Function(LO)? testLifecycleOwner}) {
    final ILifecycleRegistry registry = toLifecycleRegistry();

    final provider = registry._getViewModelProvider<LO>(
        testLifecycleOwner: testLifecycleOwner);
    if (factory != null) {
      provider.addFactory(factory);
    }
    if (factory2 != null) {
      provider.addFactory2(factory2);
    }
    return provider.get<T>();
  }
}
