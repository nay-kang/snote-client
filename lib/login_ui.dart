import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordLessLogin extends StatefulWidget {
  const PasswordLessLogin({super.key});

  @override
  State<PasswordLessLogin> createState() => _PasswordLessLoginState();
}

class _PasswordLessLoginState extends State<PasswordLessLogin> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: UsernameInput(),
        theme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: false));
  }
}

var logger = Logger();

class UsernameInput extends StatelessWidget {
  final TextEditingController nameController = TextEditingController();

  UsernameInput({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: ListView(
          children: <Widget>[
            Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: const Text(
                  'SNote',
                  style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                      fontSize: 30),
                )),
            Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: const Text(
                  'Sign in',
                  style: TextStyle(fontSize: 20),
                )),
            // using container will cause some calculation error on ios
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Email',
                ),
              ),
            ),
            Container(
                height: 50,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: ElevatedButton(
                  child: const Text('Next'),
                  onPressed: () {
                    // var toOtpCodePage = PageRouteBuilder(
                    //   pageBuilder: (context, animation, secondaryAnimation) =>
                    //       Theme(
                    //           data: Theme.of(context),
                    //           child:
                    //               OtpCodeInput(email: nameController.text)),
                    //   transitionsBuilder:
                    //       (context, animation, secondaryAnimation, child) {
                    //     const begin = Offset(1.0, 0.0);
                    //     const end = Offset.zero;
                    //     const curve = Curves.ease;

                    //     var tween = Tween(begin: begin, end: end)
                    //         .chain(CurveTween(curve: curve));

                    //     return SlideTransition(
                    //       position: animation.drive(tween),
                    //       child: child,
                    //     );
                    //   },
                    // );

                    // Navigator.of(context).push(toOtpCodePage);

                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            OtpCodeInput(email: nameController.text)));
                    Supabase.instance.client.auth
                        .signInWithOtp(email: nameController.text);
                  },
                )),
          ],
        ),
      )),
    );
  }
}

class OtpCodeInput extends StatelessWidget {
  final String email;
  OtpCodeInput({super.key, this.email = ''});

  final TextEditingController otpController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 350),
              // width: 300,
              child: ListView(
                children: <Widget>[
                  Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(10),
                      child: const Text(
                        'Code from email',
                        style: TextStyle(fontSize: 20),
                      )),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: otpController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Code',
                      ),
                    ),
                  ),
                  Container(
                      height: 50,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      child: ElevatedButton(
                        child: const Text('Submit'),
                        onPressed: () async {
                          Supabase.instance.client.auth
                              .verifyOTP(
                            email: email,
                            token: otpController.text,
                            type: OtpType.email,
                          )
                              .then((res) {
                            if (res.session != null) {
                              Navigator.of(context).pop();
                            }
                          });
                        },
                      )),
                ],
              )),
        ));
  }
}
