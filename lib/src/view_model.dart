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

extension ViewModelStoreOwnerExtension on LifecycleObserverRegistry {
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
        () => ViewModelProvider(getViewModelStore()));
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
