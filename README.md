# VideoStreamingClientAndServer

So, we want to do here at the end is we capture video using our device(client) then send it to the another device(server) plays video in realtime. It’ll look like following image in the big picture.

![image](https://user-images.githubusercontent.com/5785670/194475931-921e4c63-9aa1-45df-b0d4-13564964327a.png)


The client side needs to capture video data then send it to the network, and the server receives it over the network and play it.

video streaming technology:-

You might know that video footage is a sequence of pictures. If a video has 30 pictures in a second, we can say that it has 30 frames rate.
But that doesn’t mean video data consist of a sequence of pictures data. Why? Can you imagine how big it will be to have 30 pictures data in a second? It’ll be tremendous! So we need way more efficient strategy for delivering video data.

Basis idea here. If we have a previous picture data(we call it i-frame or key-frame) and data that represent difference between previous picture data and current picture data(we call it p-frame), we can calculate current picture data so that we can have sequence of picture data.

To recap, We can make a sequence of pictures data using one picture data and data that have difference between pictures. This is efficient in most case because a sequence of pictures data have duplicated data in common unless captured pictures doesn’t change quickly(imagine a man talking about something seating on a chair. The only changes will happen in his face.)

Converting a sequence of pictures to the video data is called compression and called decompression in reverse. Before doing compression, we have to be able to receive raw picture data so that we can compress it to video data.

![image](https://user-images.githubusercontent.com/5785670/194476217-2217372b-13f5-49e4-9d6a-850abc0395d3.png)

VideoCaptureManager class is responsible for this


Compression
Now we are able to get raw picture data so next thing we have to do is convert sequence of raw picture data to video data. There’s a lot of compression method, but we will use H.264(or called MPEG-4 Part 10) which is most popular in these days.

H264Ecoder class is responsible for this

VTCompressionSession is an object that is able to compress pictures data, so technically speaking, our H264Encoder is just a wrapper of VTCompressionSession.

And our H264Encoder class conforms to AVCaptureVideoDataOutputSampleBufferDelegate protocol to receive raw picture data stream. Note that we receive raw picture data in form of CMSampleBuffer, which is CoreMedia object that is composed of media data and its description(such as picture’s width, height..)

![image](https://user-images.githubusercontent.com/5785670/194477256-5897d5e9-686b-45fb-8fd2-8cf41ad868b2.png)

CMFormatDescription object contains SPS and PPS, CMBlockBuffer object contains other data type video data(which is mostly i-frame or p-frame). We set key frame Interval to 60 in method ‘VTSessionSetProperties’, which means we want to create one key-frame per every 60 frames. So for instance, if we have 60 frames, one frame will be a key frame and other will be p-frames.

Mind that we cannot play video only with i-frame and p-frames, they need additional information to refer to.(SPS and PPS) I hope below image get you better understand.

![image](https://user-images.githubusercontent.com/5785670/194477306-4bd4b915-c5ac-4d02-929d-fd50f9d0a133.png)


Note that we extract SPS and PPS data and add it to the naluStartCode. NAL(Network Abstraction Layer) is a way we easily handle video data for the network or our local file. We handle SPS or PPS or other frames as a NAL Unit, which is easily picked out by its start code. We usually use start code as 0x(000001) or 0x(00000001).

![image](https://user-images.githubusercontent.com/5785670/194477856-55df0c9f-6c12-4905-bc87-6de976d17d71.png)
Back to encoded CMSampleBuffer, we were able to get CMBlockBuffer from CMSampleBuffer’s dataBuffer property. CMBlockBuffer contains one or more NALU(which is mostly i-frame or p-frame but could be other types except for SPS and PPS which is included in CMFormatDescription).

But here’s a trap. It doesn’t have NALU start code, instead it contains 4 bytes NALU length information in big endian. It’ll look like following image.


![image](https://user-images.githubusercontent.com/5785670/194477884-63581783-1a1e-4b0a-82dd-bded23cd225a.png)

It’s because it could be more efficient if you do not send it over the network, let’s say you want to write it to a file, it’s way easier to pick out NALU from stream later because we just need to read 4-byte length first and read as much the length indicates. No extra effort to find start code. But we want to send it over the network, and that means it’s not always guaranteed to send NALU stream as way we want, we want to replace 4-byte length information with start code.

![image](https://user-images.githubusercontent.com/5785670/194477922-b111c563-9a47-477d-8fd7-3b226c717269.png)

And 4-byte length information is in big endian. It means if we want to read length of NALU, we need to convert it little endian because iOS system uses little endian. That’d be happened in function named ‘CFSwapInt32BigToHost’.

![image](https://user-images.githubusercontent.com/5785670/194477961-53438bc6-ba41-4d02-ad3d-5c4635fdc487.png)




Network TCPClient class is responsible for this
So far, we receive raw picture data and convert it to video data. Now we want to send it over the network. We’re gonna use Network framework, which provides straightforward ways to handle socket interface. We will first create a class named TCPClient which is responsible to behave tcp client. As you can see, it’s just a wrapper for NWConnection which will handle all network stuff for us.
