import 'package:an_lifecycle_cancellable/an_lifecycle_cancellable.dart';
import 'package:an_lifecycle_viewmodel/an_lifecycle_viewmodel.dart';
import 'package:anlifecycle/anlifecycle.dart';
import 'package:flutter/material.dart';

void main() {
  ViewModelProvider.addDefFactory2(ViewModelHome.new);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LifecycleApp(
      child: MaterialApp(
        title: 'ViewModel Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        navigatorObservers: [
          LifecycleNavigatorObserver.hookMode(),
        ],
        home: const MyHomePage(title: 'ViewModel Demo Home Page'),
      ),
    );
  }
}

class ViewModelHome with ViewModel {
  final ValueNotifier<int> counter = ValueNotifier<int>(0);

  ViewModelHome(Lifecycle lifecycle) {
    counter.bindLifecycle(lifecycle);
  }

  void incrementCounter() {
    counter.value++;
  }
}

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // 获取当前环境下的ViewModel
  late final ViewModelHome viewModel = viewModelsOfState();

  // 也可使用 当前注册的构建工厂
  // final viewModel =
  //     useLifecycleViewModelEffect<ViewModelHome>(factory2: ViewModelHome.new);
  // late final ViewModelHome viewModel = viewModels(factory2: ViewModelHome.new);

  // 从路由页来缓存 ViewModel
  // late final ViewModelHome viewModel1 = viewModelsByRouteOfState();

  // 从App 全局来缓存 ViewModel
  // late final ViewModelHome viewModel1 = viewModelsByAppOfState();

  // 当还有引用时 下次获取依然是同一个 当没有任何引用的时候 会执行清理vm
  // late final ViewModelHome viewModel1 = viewModelsByRefOfState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            AnimatedBuilder(
              animation: viewModel.counter,
              builder: (_, __) => Text(
                '${viewModel.counter.value}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: const HomeFloatingButton(),
    );
  }
}

/// 模拟子控件
class HomeFloatingButton extends StatefulWidget {
  const HomeFloatingButton({super.key});

  @override
  State<HomeFloatingButton> createState() => _HomeFloatingButtonState();
}

class _HomeFloatingButtonState extends State<HomeFloatingButton> {
  //获取vm
  late final vm = viewModelsOfState<ViewModelHome>();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: vm.incrementCounter,
      tooltip: 'Increment',
      child: const Icon(Icons.add),
    );
  }
}
