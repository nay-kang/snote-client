An app which is Simple,Security,Safefy and Speedy to take note

I used Google Keep before. but it can't work well in China. keep's features are fit for me.
then I switch to Microsoft OneNote, It could use in China, but due to it's rich features makes taking note very complex.And the sync speed is very slow,And I want use it under linux,but the webpage not work well too.

I want take note safety. so newly apps is not my choice, I don't know one day the app will go offline.And it must cross platform, has app in iOS and Android, web page on desktop will be OK.

So I start this project

My Goal is: keep it simple and handy
   
* can take text and image
* can make list and TODO
* support category or tag
* search able
* security. even server break by hackers.
* safety. if I run into bankrupt, the note data can easy tranport to other space

2023-02-27
I think "git" philosophy fit snote very well.it's decentralized. one device make note is commit new changes.other device just pulling the changes.
the server only act as a proxy or connector for devices.
and data a encriypt by a private key.server never knows the data.
but this maybe cnflict with search.local search are very pool for now.Google Keep has search problem too.

but for now.I must make the app run first.above is ideal model

2023-03-14
maybe web3 or IPFS will make this project more interest. I should make a connector or adaptor to web3 or IPFS.

2023-03-17
using git like distribution storage is a bit chanllenge for current stage. so I decide using client encrypt first.
after first regist, client generate an aes key to encrypt the note. server only store encrypted data.
if other client login, server tried to tell each other using LAN to exchange aes key. but current I stuck at web client which can't obtain local ip address.

2023-03-31
It seems snote can use client to client encryption like telegram. I will dig deeper about ECDH, I think that will help me to transport aes key between client. It only need both old client and new client online to exchange aes key.

2023-04-18
I'm not familiar with cryptography, the Diffie-Hellman can protect data exchange between insecurity connection. but I can not sure there will be other attack through long distance connection for now like man-in-the-middle. 
maybe local net transport has more security.
according to telegram, the DH encryption used with RSA which built public key into client so that only private key can descrypt. then I only ensure not lose my private key on the server. so I as provider is the only man-in-the-middle,so I have to keep my hands clean.
I want to find other zero trust solution for this.

2023-06-01
stuck at quill image.I had fix so many problems but it still has more problem.I fixed the image base problem about cross platform.but now I need to customize image default width, I can't find a way. and futher I want the images always below the text,probably there is no way either. so I decide I write this by myself and integrate into quill. hope there has less problem.

2023-06-21
after dig some research,If I want provide privacy with search.I can only using embed local search engine. and My only choice is sqlite with FTS5.
I had dig rust or other language full text, there are very rare left.

2023-06-29
there are no easy way after these days trying.
* sqflite does not support load extension.at least I search in github and google
* flutter/sqlite3 support load extension but I am not success at iOS or Android,the web version using wasm did not include fts5
* sql.js could not load extension,and it could not using db file in browser.
I decide create my custom sqlite package.I first trying fork flutter/sqlite3,and trying web first.if web success,then other platform would work too.

2023-07-19
load extension failed in web wasm. I tried direct compile libsimple into sqlite3.dart, face lots of problem, but still can't run because I had to replace sqlite3.dart wasm base package to wasm_run,so I had to rewrite lots of imports functions.
so I switch to sqlite offical wasm.and compile run successfully with pure web.now I am trying to integrate with dart. and I face choose client level worker or dedicated worker1.I can't find the dedicated worker benefit.so I choose client level worker,but worker are harder to control,it can only controlled by postMessage,so I try main thread first.

2023-08-22
in android I using custom build sqlite3(with extension enabled) and ensureExtensionLoaded function to load NDK build dynamic simple library success using the extension.next I try to package this library in aar.
in iOS dynamic library need sginature.so I first try to build a test extension.I want to using the extension without explicit load in objc.the wasm library can do this,so I trace this found a compile flag `-DSQLITE_EXTRA_INIT=func`,first try in iOS I got `EXC_BAD_ACCESS`,I try to using this flag under linux,I got `Segmentation Fault`,after a lot research I found I need add compile flag `-DSQLITE_CORE`, this [flag](https://www.sqlite.org/loadext.html) let dynamic extension can be load statically.
I did some IoT porject for entertainment during this time.

2023-09-06
after success build the sqlite with SQLITE_EXTRA_INIT package,I still can not build that with libsimple. there has some c++ library problem
* I build simple c++ plugin for sqlite, then I know I need to extern "C" to make C and C++ compatible
* after done with C C++ comaptible,I try to build libsimple with sqlite source code. got lack of c++ library problem.so I change the glue c file to cpp file to let compiler using c++ library, and change some glue code to C++.
* I want compile the libsimple by pods dependency(I used sqlite source code previously).but I failed. it seems that they still compile seperately.
* So I using flutter platform plugin to load the libsimple plugin in `registerWithRegistrar`, meet lack of C++ library problem again.I change the `registerWithRegistrar` to `mm` file.but not work,so I add `s.libraries = 'c++'` to podspec. finally it worked.

2023-09-08
Try to add libsimple to android project.previously I successed compile libsimple and manual add to project. Now I try to make the plugin as en AAR
* the sqlite3 AAR plugin do not support extension,I contact the author at github, the author may not enable the extension for me
* try to build sqlite3 by myself and download the libsimple source code using `FetchContent_Populate`,but the `cmrc_add_resource_library` do not support add file outside subdirectory,using `FetchContent_MakeAvailable` instead
* make a few adjust,successfully build libsqlite.so and libsimple.so, then try to built the two lib into one using `target_link_libraries(sqlite3 simple)` and glue code,do not work stable,some times it generate one file(modify the main CMakeLists.txt then the first rebuild would ok),sometimes it still has two shared libraries.I try to build without ndk,would not work,follow the tips it shows `OPTION(BUILD_STATIC "Option to build static lib" OFF)` would clear my set variable if the defined cmake version is older than 3.13,so I make a patch add `cmake_policy(SET CMP0077 NEW)`
* I need to replace `sqlite3-native-library` with my custom sqlite3.I try to using `resolutionStrategy` to resolve conflict,but I can not import local aar file in resolutionStrategy,I had to publish my package to local maven repo

2023-10-17
stuck at link web plugin javascript assets for two days.there is no anwser about this,the nearest result is import_js_plugin,but it's too old can not compatible with dart3.  
I want learn from exists packages, but most package do not have local javascript asset.finally I found fluttertoast has local javascript,And I learned that the link partten of local javascript is `assets/packages/$package_name/$package_assset_path`,in my package the path is `assets/packages/libsimple_flutter/assets/sqlite3bridge.js`.  
the fluttertoast using `ui.webOnlyAssetManager.getAssetUrl` to translate url,but I do not find offical document about this.

2023-10-30
the problem of sync deleted content.there are two type of deletion,soft and hard,soft just change note status and can be restore. hard is truely delete from recycle bin and free up space.
because it's purged in under layer,so there should no way to let other client knows unless make storage for the deletions even it using message queue.  
so at current stage I still store the deletions in database,but wipe the note content only keep the note id. and this will deleted untill all client is newer then this.
DB prepare statement.currently I can only allow execute raw sql in web wasm.but the note content are in many kinds of.I need prepare statement.  
but wait,because the content are in many forms,I already encode it to JSON,so I can save it into database.solved! but as a public plugin,I should add prepare statement support.

2023-11-02
get stucked at "Cross-Origin-Embedder-Policy".the jsdelivr do not support add this header,the flutter local dev server would not support either.and I after switch to https server and add headers, it also need me to run in worker.I test that with sqlite offical demo-123-worker.and I had to change oo1.DB to oo1.OpfsDb().
next I had to figure out how to make worker postMessage works like function call the could return query result.

2023-12-22
dart really sucks on something.like I can run this list destructure code in `DartPad`
```dart
void main() {
  var a = [1,2,3];
  var [b,...c] = a;
  print(b);
}
```
but I can not run it in my project.
another is enum.I can define a enum with custom value.but I can not direct using it. I had to define a method to map a custom int value to enum
```dart
enum NoteStatus {
  normal(1),
  softDelete(-1),
  hardDelete(-2);

  const NoteStatus(this.value);
  final num value;

  static NoteStatus getByValue(num i) {
    return NoteStatus.values.firstWhere((x) => x.value == i);
  }
}
```

2024-01-04
I want show a global loading bar on top of screen when there has http request.but after google search and some ask GPT.there is no perfect answer.
And I can not understand widgets and navigator.which means I write the loading bar in a parent widget.but when I navigator out,then the loading bar will not work.
at last using Overlay to figure it out.

2025-04-08
flutter rich text input has problem with chrome."https://flutter.github.io/samples/web/simplistic_editor/" in this example when put massive text and then select text.the selected area is wrong.this happened on both linux and windows.
and linux chrome has input method posistion problem.that the input method widget float far away from the focus position when chrome not align left of the screen.

2025-09-27
about search.for this project the recall is the most important.and the footprint is the second important one dure it need run in web browser. rank,speed and other feature is not important for this project.  
so the importtant of important is tokenizer for this project.