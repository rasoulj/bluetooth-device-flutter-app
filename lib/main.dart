// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_bt_test/chash.dart';
import 'package:app_bt_test/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(FlutterBluePlusApp());
}

class FlutterBluePlusApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothState>(
          stream: FlutterBluePlus.instance.state,
          initialData: BluetoothState.unknown,
          builder: (c, snapshot) {
            // final state = snapshot.data;
            // if (state == BluetoothState.on) {
              return FindDevicesScreen();
            // }
            // return BluetoothOffScreen(state: state);
          }),
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({Key key, this.state}) : super(key: key);

  final BluetoothState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bluetooth_disabled,
              size: 200.0,
              color: Colors.white54,
            ),
            Text(
              'Bluetooth Adapter is ${state != null ? state.toString().substring(15) : 'not available'}.',
            ),
          ],
        ),
      ),
    );
  }
}

class FindDevicesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () => FlutterBluePlus.instance.startScan(timeout: Duration(milliseconds: 500)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Row(
                children: [
                  ElevatedButton(
                    child: Text("set s0"),
                    onPressed: () async {
                      setSwitch(0, 0, 2000);
                    },
                  ),
                  SizedBox(width: 64),
                  ElevatedButton(
                    child: Text("set s1"),
                    onPressed: () async {
                      setSwitch(1, 0, 2000);
                    },
                  ),
                ],
                mainAxisAlignment: MainAxisAlignment.center,
              ),
              StreamBuilder<List<BluetoothDevice>>(
                stream: Stream.periodic(Duration(milliseconds: 500))
                    .asyncMap((_) => FlutterBluePlus.instance.connectedDevices),
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data
                      .map((d) => ListTile(
                            title: Text(d.name),
                            subtitle: Text(d.id.toString()),
                            trailing: StreamBuilder<BluetoothDeviceState>(
                              stream: d.state,
                              initialData: BluetoothDeviceState.disconnected,
                              builder: (c, snapshot) {
                                if (snapshot.data == BluetoothDeviceState.connected) {
                                  return ElevatedButton(
                                    child: Text('OPEN'),
                                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (context) => DeviceScreen(device: d))),
                                  );
                                }
                                return Text(snapshot.data.toString());
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBluePlus.instance.scanResults,
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data
                      .map(
                        (r) => ScanResultTile(
                          result: r,
                          onTap: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                            r.device.connect();
                            return DeviceScreen(device: r.device);
                          })),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBluePlus.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data) {
            return FloatingActionButton(
              child: Icon(Icons.stop),
              onPressed: () => FlutterBluePlus.instance.stopScan(),
              backgroundColor: Colors.red,
            );
          } else {
            return FloatingActionButton(
                child: Icon(Icons.search),
                onPressed: () => FlutterBluePlus.instance.startScan(timeout: Duration(seconds: 4)));
          }
        },
      ),
    );
  }

  /// set [switchInd] to [state] (can be 0 or 1) for [duration] milliseconds
  setSwitch(int switchInd, int state, int duration) async {
    final sw = Stopwatch()..start();
    final List<ScanResult> devices =
        await FlutterBluePlus.instance.startScan(timeout: Duration(milliseconds: 500));
    await FlutterBluePlus.instance.stopScan();

    final esp = devices.firstWhere((dev) => dev.device.name == "ESP32", orElse: () => null);
    try {
      print("esp.device.id.id: ${esp.device.id.id}");
      await esp.device.connect(timeout: Duration(seconds: 250));
      // final mtu = await esp.device.mtu.first;
      final services = await esp.device.discoverServices();
      final BluetoothService service = services.firstWhere((element) {
        final uuid = element.uuid.toString().toUpperCase();
        return uuid == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
      }, orElse: () => null);
      final mtu = await esp.device.mtu.first;
      print("connected with $mtu");
      final rx_char = service.characteristics.firstWhere(
          (element) =>
              element.uuid.toString().toUpperCase() == "6E400002-B5A3-F393-E0A9-E50E24DCCA9E",
          orElse: () => null);
      final tx_charachteristic = service.characteristics.firstWhere(
          (element) =>
              element.uuid.toString().toUpperCase() == "6E400003-B5A3-F393-E0A9-E50E24DCCA9E",
          orElse: () => null);

      final rb = String.fromCharCodes(await tx_charachteristic.read());
      final int seed = jsonDecode(rb)["seed"];

      print("vv = $rb, seed=$seed");

      final cmd = "sw $switchInd $state $duration";
      // final json = jsonEncode({"cmd": cmd, "h": CHash.hash(cmd), "hs": CHash.hash_with_seed(cmd, seed)});
      final json = jsonEncode({"cmd": cmd});
      print("sending json=$json ${json.codeUnits}");
      await rx_char.write(json.codeUnits);
      await esp.device.disconnect();
      print("disconnected in ${sw.elapsedMilliseconds}ms");
    } catch (e) {
      print("error=$e");
      rethrow;
    }
  }
}

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({Key key, @required this.device}) : super(key: key);

  final BluetoothDevice device;

  List<int> _getRandomBytes() {
    final math = Random();
    return [math.nextInt(255), math.nextInt(255), math.nextInt(255), math.nextInt(255)];
  }

  List<Widget> _buildServiceTiles(List<BluetoothService> services) {
    return services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics
                .map(
                  (c) => CharacteristicTile(
                    characteristic: c,
                    onReadPressed: () => c.read(),
                    onWritePressed: () async {
                      await c.write(
                          "this is a long string which would be replaced with a json later manybe?"
                              .codeUnits,
                          withoutResponse: false);
                      await c.read();
                    },
                    onNotificationPressed: () async {
                      await c.setNotifyValue(!c.isNotifying);
                      await c.read();
                    },
                    descriptorTiles: c.descriptors
                        .map(
                          (d) => DescriptorTile(
                            descriptor: d,
                            onReadPressed: () => d.read(),
                            onWritePressed: () => d.write(_getRandomBytes()),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: <Widget>[
          StreamBuilder<BluetoothDeviceState>(
            stream: device.state,
            initialData: BluetoothDeviceState.connecting,
            builder: (c, snapshot) {
              VoidCallback onPressed;
              String text;
              switch (snapshot.data) {
                case BluetoothDeviceState.connected:
                  onPressed = () => device.disconnect();
                  text = 'DISCONNECT';
                  break;
                case BluetoothDeviceState.disconnected:
                  onPressed = () => device.connect();
                  text = 'CONNECT';
                  break;
                default:
                  onPressed = null;
                  text = snapshot.data.toString().substring(21).toUpperCase();
                  break;
              }
              return ElevatedButton(
                  onPressed: onPressed,
                  child: Text(
                    text,
                    style: Theme.of(context).primaryTextTheme.button?.copyWith(color: Colors.white),
                  ));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            StreamBuilder<BluetoothDeviceState>(
              stream: device.state,
              initialData: BluetoothDeviceState.connecting,
              builder: (c, snapshot) => ListTile(
                leading: (snapshot.data == BluetoothDeviceState.connected)
                    ? Icon(Icons.bluetooth_connected)
                    : Icon(Icons.bluetooth_disabled),
                title: Text('Device is ${snapshot.data.toString().split('.')[1]}.'),
                subtitle: Text('${device.id}'),
                trailing: StreamBuilder<bool>(
                  stream: device.isDiscoveringServices,
                  initialData: false,
                  builder: (c, snapshot) => IndexedStack(
                    index: snapshot.data ? 1 : 0,
                    children: <Widget>[
                      IconButton(
                        icon: Icon(Icons.refresh),
                        onPressed: () => device.discoverServices(),
                      ),
                      IconButton(
                        icon: SizedBox(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.grey),
                          ),
                          width: 18.0,
                          height: 18.0,
                        ),
                        onPressed: null,
                      )
                    ],
                  ),
                ),
              ),
            ),
            StreamBuilder<int>(
              stream: device.mtu,
              initialData: 0,
              builder: (c, snapshot) => ListTile(
                title: Text('MTU Size'),
                subtitle: Text('${snapshot.data} bytes'),
                trailing: IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () => device.requestMtu(223),
                ),
              ),
            ),
            StreamBuilder<List<BluetoothService>>(
              stream: device.services,
              initialData: [],
              builder: (c, snapshot) {
                return Column(
                  children: _buildServiceTiles(snapshot.data),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
