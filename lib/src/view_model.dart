import 'dart:async';
import 'dart:collection';

import 'package:an_lifecycle_cancellable/an_lifecycle_cancellable.dart';
import 'package:anlifecycle/anlifecycle.dart';
import 'package:cancellable/cancellable.dart';
import 'package:weak_collections/weak_collections.dart' as weak;

abstract class ViewModel {
  bool _mCleared = false;
  final Set<Cancellable> _closeables = {};

  void onCleared() {}

  addCloseable(Cancellable closeable) {
    if (_mCleared) return;
    _closeables.add(closeable);
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

typedef ViewModelFactory<T extends ViewModel> = T Function();

class _ViewModelDefFactories {
  static final _ViewModelDefFactories _instance = _ViewModelDefFactories();

  final Map<Type, ViewModelFactory> _factoryMap = {};

  void addFactory<T extends ViewModel>(ViewModelFactory<T> factory) {
    _factoryMap[T] = factory;
  }
}

class ViewModelProvider {
  final ViewModelStore _viewModelStore;
  final Map<Type, ViewModelFactory> _factoryMap = {};

  ViewModelProvider(this._viewModelStore);

  T get<T extends ViewModel>() {
    var vm = _viewModelStore.get(T.toString());
    if (vm != null && vm is T) return vm;

    if (_factoryMap.containsKey(T)) {
      ViewModelFactory<T> factory = _factoryMap[T] as ViewModelFactory<T>;
      vm = factory();
      _viewModelStore.put(T.toString(), vm);
      return vm;
    }
    if (_ViewModelDefFactories._instance._factoryMap.containsKey(T)) {
      ViewModelFactory<T> factory = _ViewModelDefFactories
          ._instance._factoryMap[T] as ViewModelFactory<T>;
      vm = factory();
      _viewModelStore.put(T.toString(), vm);
      return vm;
    }
    throw 'cannot find $T factory';
  }

  addFactory<T extends ViewModel>(ViewModelFactory<T> factory) =>
      _factoryMap[T] = factory;

  static void addDefFactory<T extends ViewModel>(ViewModelFactory<T> factory) =>
      _ViewModelDefFactories._instance.addFactory(factory);
}

Map<Lifecycle, ViewModelStore> _viewModelStore = HashMap();
Map<Lifecycle, ViewModelProvider> _viewModelProvider = HashMap();

extension ViewModelStoreOwnerExtension on LifecycleObserverRegistry {
  ViewModelStore getViewModelStore() =>
      _viewModelStore.putIfAbsent(lifecycle, () {
        final store = ViewModelStore();
        lifecycle.addObserver(LifecycleObserver.onEventDestroy(
            (owner) => _viewModelStore.remove(owner.lifecycle)?.clear()));
        return store;
      });

  ViewModelProvider getViewModelProvider() {
    assert(currentLifecycleState > LifecycleState.destroyed,
        'Must be used before destroyed.');
    return _viewModelProvider.putIfAbsent(lifecycle, () {
      final provider = ViewModelProvider(getViewModelStore());
      lifecycle.addObserver(LifecycleObserver.onEventDestroy(
          (owner) => _viewModelProvider.remove(owner.lifecycle)));
      return provider;
    });
  }

  T viewModels<T extends ViewModel>({ViewModelFactory<T>? factory}) {
    final provider = getViewModelProvider();
    if (factory != null) {
      provider.addFactory(factory);
    }
    return provider.get<T>();
  }

  T viewModelsByRoute<T extends ViewModel>({ViewModelFactory<T>? factory}) =>
      viewModelsByLifecycleOwner<T, LifecycleRouteOwnerState>(factory: factory);

  T viewModelsByApp<T extends ViewModel>({ViewModelFactory<T>? factory}) =>
      viewModelsByLifecycleOwner<T, LifecycleAppOwnerState>(
          factory: factory,
          testLifecycleOwner: (owner) => owner.lifecycle.parent == null);

  T viewModelsByLifecycleOwner<T extends ViewModel,
          LO extends LifecycleOwnerStateMixin>(
      {ViewModelFactory<T>? factory, bool Function(LO)? testLifecycleOwner}) {
    final provider =
        _getViewModelProvider<LO>(testLifecycleOwner: testLifecycleOwner);
    if (factory != null) {
      provider.addFactory(factory);
    }
    return provider.get<T>();
  }

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
    if (test == null) {
      Lifecycle? life = lifecycle;
      while (life != null) {
        if (life is LifecycleRegistry && life.provider is LO) {
          return (life.provider as LO);
        }
        life = life.parent;
      }
      return null;
    }
    Lifecycle? life = lifecycle;
    while (life != null) {
      if (life is LifecycleRegistry &&
          life.provider is LO &&
          test((life.provider as LO))) {
        return (life.provider as LO);
      }
      life = life.parent;
    }
    return null;
  }
}

class LifecycleScope {
  final LifecycleObserverRegistry _registry;

  LifecycleScope(this._registry);

  Future<R> launchOnState<R>(
          {LifecycleState state = LifecycleState.started,
          required FutureOr<R> Function() block}) =>
      _registry.whenMoreThanState(state).then((value) => block());

  Future<R> launchOnNextState<R>(
          {LifecycleState state = LifecycleState.started,
          required FutureOr<R> Function() block}) =>
      _registry.nextLifecycleState(state).then((value) => block());

  Future<R> launchOnStarted<R>({required FutureOr<R> Function() block}) =>
      launchOnState(state: LifecycleState.started, block: block);

  Future<R> launchOnResumed<R>({required FutureOr<R> Function() block}) =>
      launchOnState(state: LifecycleState.resumed, block: block);

  Future<R> launchOnNextStarted<R>({required FutureOr<R> Function() block}) =>
      launchOnNextState(state: LifecycleState.started, block: block);

  Future<R> launchOnNextResumed<R>({required FutureOr<R> Function() block}) =>
      launchOnNextState(state: LifecycleState.resumed, block: block);
}

class _VMLifecycleObserver<VM extends ViewModel>
    with LifecycleStateChangeObserver {
  final VM _viewModel;

  LaunchWhen<VM>? launchWhenCreated;
  LaunchWhen<VM>? launchWhenStarted;
  LaunchWhen<VM>? launchWhenResumed;
  Map<LifecycleState, LaunchWhen<VM>> _repeatOn = {};

  _VMLifecycleObserver(this._viewModel);

  bool _firstCreate = true, _firstStart = true, _firstResume = true;

  @override
  void onStateChange(LifecycleOwner owner, LifecycleState state) {
    if (_firstCreate &&
        state == LifecycleState.created &&
        launchWhenCreated != null) {
      _firstCreate = false;
      launchWhenCreated!(_viewModel);
    } else if (_firstStart &&
        state == LifecycleState.started &&
        launchWhenStarted != null) {
      _firstStart = false;
      launchWhenStarted!(_viewModel);
    } else if (_firstResume &&
        state == LifecycleState.resumed &&
        launchWhenResumed != null) {
      _firstResume = false;
      launchWhenResumed!(_viewModel);
    }
    _repeatOn[state]?.call(_viewModel);
  }
}

Map<ViewModel, _VMLifecycleObserver> _vmObservers = weak.WeakMap();

typedef LaunchWhen<VM extends ViewModel> = FutureOr Function(VM viewModel);

extension LifecycleObserverRegistryWithLifecyle on LifecycleObserverRegistry {
  void withLifecycleScopeViewModelLaunch<VM extends ViewModel>({
    VM? viewModel,
    ViewModelFactory<VM>? factory,
    LaunchWhen<VM>? launchWhenCreated,
    LaunchWhen<VM>? launchWhenStarted,
    LaunchWhen<VM>? launchWhenResumed,
    LaunchWhen<VM>? repeatOnStarted,
    LaunchWhen<VM>? repeatOnResumed,
  }) {
    if (launchWhenCreated == null &&
        launchWhenStarted == null &&
        launchWhenResumed == null &&
        repeatOnStarted == null &&
        repeatOnResumed == null) {
      return;
    }

    final vm = viewModel ?? viewModels<VM>(factory: factory);

    final observer = _vmObservers.putIfAbsent(vm, () {
      final o = _VMLifecycleObserver<VM>(vm);
      o.launchWhenCreated = launchWhenCreated;
      o.launchWhenStarted = launchWhenStarted;
      o.launchWhenResumed = launchWhenResumed;

      if (repeatOnStarted != null) {
        o._repeatOn[LifecycleState.started] = repeatOnStarted;
      }
      if (repeatOnResumed != null) {
        o._repeatOn[LifecycleState.resumed] = repeatOnResumed;
      }

      addLifecycleObserver(o);
      return o;
    }) as _VMLifecycleObserver<VM>;

    if (repeatOnStarted != null) {
      observer._repeatOn[LifecycleState.started] = repeatOnStarted;
    }
    if (repeatOnResumed != null) {
      observer._repeatOn[LifecycleState.resumed] = repeatOnResumed;
    }
  }
}
