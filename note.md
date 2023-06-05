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