import 'dart:async';

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
        title: 'Lifecycle ViewModel Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        navigatorObservers: [
          LifecycleNavigatorObserver.hookMode(),
        ],
        home: const MyHomePage(title: 'Lifecycle ViewModel Demo Home Page'),
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

class _MyHomePageState extends State<MyHomePage>
    with LifecycleRegistryStateMixin {
  late final ValueNotifier<int> stayed = ValueNotifier(0);

  late final ViewModelHome viewModel = viewModels();

  // 也可使用 当前注册的构建工厂
  // final viewModel =
  //     useLifecycleViewModelEffect<ViewModelHome>(factory2: ViewModelHome.new);
  // late final ViewModelHome viewModel = viewModels(factory2: ViewModelHome.new);

  @override
  void initState() {
    super.initState();
    stayed
        .bindLifecycle(this)
        .addCListener(makeLiveCancellable(), () => setState(() {}));

    // 只有可见时统计时间 不可见时不统计
    Stream.periodic(const Duration(seconds: 1))
        .bindLifecycle(this, repeatLastOnRestart: true)
        .listen((event) => stayed.value++);

    viewModel.counter
        .addCListener(makeLiveCancellable(), () => setState(() {}));
  }

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
            Text(
              'Stayed on this page for:${stayed.value} s',
            ),
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '${viewModel.counter.value}',
              style: Theme.of(context).textTheme.headlineMedium,
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

class _HomeFloatingButtonState extends State<HomeFloatingButton>
    with LifecycleRegistryStateMixin {
  @override
  Widget build(BuildContext context) {
    //获取vm
    final vm = viewModels<ViewModelHome>();
    return FloatingActionButton(
      onPressed: vm.incrementCounter,
      tooltip: 'Increment',
      child: const Icon(Icons.add),
    );
  }
}
