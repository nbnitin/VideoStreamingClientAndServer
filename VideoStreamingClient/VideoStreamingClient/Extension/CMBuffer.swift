//
//  CMBuffer.swift
//  VideoStreamingClient
//
//  Created by Nitin Bhatia on 07/10/22.
//

import Foundation
import AVFoundation

//So, If a given CMSampleBuffer represents i-frame(key-frame), we need to extract SPS and PPS from it.
//
//First, we will extend CMSampleBuffer easily tell it represents key frame.

extension CMSampleBuffer {
    var isKeyFrame: Bool {
        let attachments =  CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: true) as? [[CFString: Any]]
        
        let isNotKeyFrame = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        
        return !isNotKeyFrame
    }
}
