//
//  ViewController.swift
//  VideoStreamingClient
//
//  Created by Nitin Bhatia on 07/10/22.
//

import UIKit

class ViewController: UIViewController {
    
    
    @IBOutlet weak var btnStart: UIButton!
    @IBOutlet weak var txtServerAddress: UITextField!
    
    let videoClient = VideoClient()
        
    override func viewDidLoad() {
        super.viewDidLoad()
        btnStart.setTitle("Start", for: .normal)
        btnStart.setTitle("Stop", for: .selected)
    }
    
    @IBAction func btnStartAction(_ sender: UIButton) {
        
        if ((txtServerAddress.text?.isEmpty) != nil) {
            return
        }
        
        if btnStart.isSelected {
            videoClient.stopConnection()
            btnStart.isSelected.toggle()
            return
        }
        
        guard let ipAddress = txtServerAddress.text else { return }
        
        do {
            try videoClient.connect(to: ipAddress, with: 12005)
            try videoClient.startSendingVideoToServer()
        } catch {
            print("error occured : \(error.localizedDescription)")
        }
        
        btnStart.isSelected.toggle()
    }

}

