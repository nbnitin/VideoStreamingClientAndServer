//
//  H264Encoder.swift
//  VideoStreamingClient
//
//  Created by Nitin Bhatia on 07/10/22.
//

import AVFoundation
import VideoToolbox

/// Abstract: An Object recieves raw video data and encode it to H264 Format
class H264Encoder: NSObject {
    
    enum ConfigurationError: Error {
        case cannotCreateSession
        case cannotSetProperties
        case cannotPrepareToEncode
    }
    
    // MARK: - dependencies
    
    private var _session: VTCompressionSession!
    
    // MARK: - nalu hanlding
    
    private static let naluStartCode = Data([UInt8](arrayLiteral: 0x00, 0x00, 0x00, 0x01))
    var naluHandling: ((Data) -> Void)?
        
    // MARK: - init
    
    override init() {
        super.init()
    }
    
    // MARK: - configure session
    
    /// create VTCompressSession with default settings
    func configureCompressSession() throws {
        let error = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                             width: Int32(720),
                                             height: Int32(1280),
                                             codecType: kCMVideoCodecType_H264,
                                             encoderSpecification: nil,
                                             imageBufferAttributes: nil,
                                             compressedDataAllocator: kCFAllocatorDefault,
                                             outputCallback: encodingOutputCallback,
                                             refcon: Unmanaged.passUnretained(self).toOpaque(),
                                             compressionSessionOut: &_session)
        
        guard error == errSecSuccess,
              let session = _session else {
            throw ConfigurationError.cannotCreateSession
        }
        
        let propertyDictionary = [
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Baseline_AutoLevel,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 60,
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_Quality: 0.5,
        ] as CFDictionary
        
        guard VTSessionSetProperties(session, propertyDictionary: propertyDictionary) == noErr else {
            throw ConfigurationError.cannotSetProperties
        }
        
        guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else {
            throw ConfigurationError.cannotPrepareToEncode
        }
        
        print("VTCompressSession is ready to use")
    }
    
    // MARK: - encoding output callback
    //‘VTCompressionSessionEncodeFrame’ method will encode raw picture data and call callback method we previously provided in VTCompressionSessionCreate method.
    
   // It’s time to declare encodingOutputCallback :
    /// it's called when VTCompressSession completes encode
    /// raw video data to h264 format data
    private var encodingOutputCallback: VTCompressionOutputCallback = { (outputCallbackRefCon: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?, status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) in
        guard let sampleBuffer = sampleBuffer else {
            print("nil buffer")
            return
        }
        guard let refcon: UnsafeMutableRawPointer = outputCallbackRefCon else {
            print("nil pointer")
            return
        }
        guard status == noErr else {
            print("encoding failed")
            return
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            print("CMSampleBuffer is not ready to use")
            return
        }
        guard flags != VTEncodeInfoFlags.frameDropped else {
            print("frame dropped")
            return
        }
        
        let encoder: H264Encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        
        // if the encoded frame is key frame, we need to extract sps and pps data from it
        if sampleBuffer.isKeyFrame {
            encoder.extractSPSAndPPS(from: sampleBuffer)
        }
        
        // dataBuffer is wrapper for media data(here it is h264 format)
        guard let dataBuffer = sampleBuffer.dataBuffer else { return }
        
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let error = CMBlockBufferGetDataPointer(dataBuffer,
                                                atOffset: 0,
                                                lengthAtOffsetOut: nil,
                                                totalLengthOut: &totalLength,
                                                dataPointerOut: &dataPointer)
        
        guard error == kCMBlockBufferNoErr,
              let dataPointer = dataPointer else { return }
        
        var packageStartIndex = 0
        
        // dataPointer has several NAL units which respectively is
        // composed of 4 bytes data represents NALU length and pure NAL unit.
        // To reduce confusion, i call it a package which represents (4 bytes NALU length + NAL Unit)
        while packageStartIndex < totalLength {
            var nextNALULength: UInt32 = 0
            memcpy(&nextNALULength, dataPointer.advanced(by: packageStartIndex), 4)
            // First four bytes of package represents NAL unit's length in Big Endian.
            // We should convert Big Endian Representation to Little Endian becasue
            // nextNALULength variable here should be representation of human readable number.
            nextNALULength = CFSwapInt32BigToHost(nextNALULength)
            
            var nalu = Data(bytes: dataPointer.advanced(by: packageStartIndex+4),
                            count: Int(nextNALULength))
            
            packageStartIndex += (4 + Int(nextNALULength))
            
            encoder.naluHandling?(H264Encoder.naluStartCode + nalu)
        }
    }
    
    // MARK: - helper methods
    
//    encodingOutputCallback is a type of VTCompressionOutputCallback which takes some parameters :
//
//    outputCallbackRefCon : Provided outputCallbackRefCon in method VTCompressionSessionCreate and in this case it’ll be H264Encoder.
//    sampleBuffer : encoded frame in form of CMSampleBuffer
//    Now, we finally get encoded frame(video data) in our ‘encodingOutputCallback’ closure. But what is it?
//
//    In H.264, there’s several types of data that represent video related data or format related data. There’s a lot of more types, it’d be no problem to know four types for the time being.
//
//    i-frame(key-frame) : Full picture data. we can represent an image without any further
//    p-frame : Predictive data. It represents difference between pictures and we can use it calculate next picture data from previous one.
//    PPS(Picture Parameter Set) : It’s not directly related to video but it represents some auxiliary data a picture refer to such as picture’s width and height info.
//    SPS(Sequence Parameter Set) : It’s similar to PPS, but a sequence of video frames refer to this data not a single picture.
//    Back to our encoded CMSampleBuffer, let’s see how it’s related to H.264 data type i just explained.
    
  //  And we need a method to extract SPS and PPS from CMSampleBuffer if it’s a key frame.
    
    private func extractSPSAndPPS(from sampleBuffer: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        var parameterSetCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           parameterSetIndex: 0,
                                                           parameterSetPointerOut: nil,
                                                           parameterSetSizeOut: nil,
                                                           parameterSetCountOut: &parameterSetCount,
                                                           nalUnitHeaderLengthOut: nil)
        guard parameterSetCount == 2 else { return }
        
        var spsSize: Int = 0
        var sps: UnsafePointer<UInt8>?
        
        // get sps data and it's size
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           parameterSetIndex: 0,
                                                           parameterSetPointerOut: &sps,
                                                           parameterSetSizeOut: &spsSize,
                                                           parameterSetCountOut: nil,
                                                           nalUnitHeaderLengthOut: nil)
        
        var ppsSize: Int = 0
        var pps: UnsafePointer<UInt8>?
        
        // get pps data and it's size
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           parameterSetIndex: 1,
                                                           parameterSetPointerOut: &pps,
                                                           parameterSetSizeOut: &ppsSize,
                                                           parameterSetCountOut: nil,
                                                           nalUnitHeaderLengthOut: nil)
        guard let sps = sps,
              let pps = pps else { return }
        
        [Data(bytes: sps, count: spsSize), Data(bytes: pps, count: ppsSize)].forEach {
            naluHandling?(H264Encoder.naluStartCode + $0)
        }
    }
    
    //A Function named ‘VTCompressionSessionCreate’ is a C function that create VTCompressionSession. And many of core library’s functions in Swift are C functions. You may not be familiar to using C function in Swift, but you don’t need to be scary. It looks a little different from Swift’s, but not that much.
    
//    ‘VTCompressionSessionCreate’ takes some parameters:
//
//    outputCallback : If encoding task is completed, the outputCallback closure will be called. You can think of it as a completion callback. We will declare this closure later.
//    outputCallbackRefCon : The object that retain outputCallback closure. In this case it’ll be H264Encoder instance and we need to pass it as a pointer so we used some magic code here(Unmanaged.passUnretained(self).toOpaque).
//    compressionSessionOut : A pointer that will contain created VTCompressionSession. We could pass our _session as a pointer using ampersand(&)
//    In VTSessionSetProperties and VTCompressionSessionPrepareToEncodeFrames methods, we set some properties and got the session ready to use.
//
//    We are now able to convert raw picture data to video data.
    private func encode(buffer: CMSampleBuffer) {
        guard let session = _session,
              let px = CMSampleBufferGetImageBuffer(buffer) else { return }
        let timeStamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        let duration = CMSampleBufferGetDuration(buffer)
        
        VTCompressionSessionEncodeFrame(session,
                                        imageBuffer: px,
                                        presentationTimeStamp: timeStamp,
                                        duration: duration,
                                        frameProperties: nil,
                                        sourceFrameRefcon: nil,
                                        infoFlagsOut: nil)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension H264Encoder: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // a point to receive raw video data
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        encode(buffer: sampleBuffer)
    }
}

