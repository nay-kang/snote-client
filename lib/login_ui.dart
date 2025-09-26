import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'auth.dart';

var logger = Logger();

class PasswordLessLogin extends StatelessWidget {
  const PasswordLessLogin({super.key});

  @override
  Widget build(BuildContext context) {
    return UsernameInput();
  }
}

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
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            OtpCodeInput(email: nameController.text)));
                    AuthManager.getInstance().requestOtp(nameController.text);
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

  // new helper method to submit OTP
  void _submitOTP(BuildContext context) {
    AuthManager.getInstance()
        .login(
      email: email,
      otpCode: otpController.text,
    )
        .then((res) {
      if (res) {
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

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
                      keyboardType: TextInputType.phone,
                      onSubmitted: (_) =>
                          _submitOTP(context), // trigger submit on Enter key
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
                        onPressed: () => _submitOTP(context),
                      )),
                ],
              )),
        ));
  }
}
