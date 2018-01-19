//
//  DeviceViewController.swift
//  Firefly Activity
//
//  Created by Denis Bohm on 1/10/18.
//  Copyright © 2018 Firefly Design LLC. All rights reserved.
//

import UIKit
import CoreBluetooth
import FireflyDevice

class DeviceViewController: UIViewController, FDPullTaskDelegate, PlotViewDelegate {
    
    class Logger {
        
        var viewController: DeviceViewController? = nil
        
        func log(line: String) {
            guard let statusLabel = viewController?.statusLabel else {
                return
            }
            statusLabel.text = line
        }
        
        func progressActive() {
            viewController?.progressView.isHidden = false
        }
        
        func setProgress(_ progress: Float) {
            viewController?.progressView.setProgress(progress, animated: true)
        }
        
        func progressInactive() {
            viewController?.progressView.isHidden = true
        }
        
    }
    
    @IBOutlet var deviceNameLabel: UILabel!
    @IBOutlet var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet var plotView: PlotView!
    @IBOutlet var statusLabel: UILabel!
    @IBOutlet var progressView: UIProgressView!
    
    let logger = Logger()
    var queryRange = (start: 0.0, end: 1.0)
    var fireflyIce: FDFireflyIce? = nil
    
    var backCallback: (() -> Void)? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        
        logger.viewController = self
        
        plotView.plotViewDelegate = self
        
        viewAll()
    }
    
    @IBAction func back() {
        if let callback = backCallback {
            callback()
        }
    }

    func showDevice(fireflyIce: FDFireflyIce) {
        self.fireflyIce = fireflyIce
        
        deviceNameLabel.text = fireflyIce.name
        
        // invalidate the data in the plot view
        queryRange = (start: 0.0, end: 1.0)
        viewAll()
    }
    
    func stop() {
        activityIndicatorView.stopAnimating()
        
        if let channel = fireflyIce?.channels["BLE"] as? FDFireflyIceChannelBLE {
            channel.close()
        }
        fireflyIce = nil
    }
    
    func cancel() {
        fireflyIce?.executor.cancelAll()
        
        viewAll()
    }
    
    func viewAll() {
        let end = Date()
        let calendar = NSCalendar(calendarIdentifier: NSCalendar.Identifier.gregorian)!
        let start = calendar.date(byAdding: .day, value: -7, to: end)!
        plotView.setTimeAxis(min: start.timeIntervalSince1970, max: end.timeIntervalSince1970)
        plotView.setTimeAxisEnded()
    }
    
    func storageType(_ a: String, _ b: String, _ c: String, _ d: String) -> NSNumber {
        let b0 = UnicodeScalar(a)!.value
        let b1 = UnicodeScalar(b)!.value << 8
        let b2 = UnicodeScalar(c)!.value << 16
        let b3 = UnicodeScalar(d)!.value << 24
        return NSNumber(value: b0 | b1 | b2 | b3)
    }

    func pullActivityData() {
        guard let fireflyIce = fireflyIce else {
            return
        }
        logger.log(line: "syncing")
        
        let hardwareIdentifier = FDHardwareId.hardwareId(fireflyIce.hardwareId.unique)
        let channel = fireflyIce.channels["BLE"] as! FDFireflyIceChannelBLE
        let pullTask = FDPullTask()
        pullTask.hardwareId = hardwareIdentifier
        pullTask.fireflyIce = fireflyIce
        pullTask.channel = channel
        pullTask.delegate = self
        pullTask.identifier = "pull"
        pullTask.timeout = 300.0
        pullTask.upload = DatastoreInsert(identifier: hardwareIdentifier, delegate: pullTask)
        let vmaDecoder = FDVMADecoder()
        let vmaType  = storageType("F", "D", "V", "2")
        pullTask.decoderByType[vmaType] = vmaDecoder
        fireflyIce.executor.execute(pullTask)
    }
    
    func pullTaskActive(_ task: FDPullTask) {
        logger.progressActive()
    }
    
    func pullTask(_ task: FDPullTask, progress: Float) {
        logger.setProgress(progress)
    }
    
    func pullTaskInactive(_ task: FDPullTask) {
        logger.progressInactive()
        viewAll()
        
        if let channel = self.fireflyIce?.channels["BLE"] as? FDFireflyIceChannelBLE {
            channel.close()
        }
    }

    func queryActivity(start: Double, end: Double) {
        let identifier: String
        if let fireflyIce = fireflyIce {
            identifier = FDHardwareId.hardwareId(fireflyIce.hardwareId.unique)
        } else {
            identifier = "anonymous"
        }
        queryRange = (start: start, end: end)
        plotView.query(identifier: identifier, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }
    
    func plotView(timeAxisChange viewRange: (start: Double, end: Double)) {
        // if new range is outside last queried range, run a new query
        if (viewRange.start < queryRange.start) || (viewRange.end > queryRange.end) {
            // load more data beyond the view, to minimize future queries
            let interval = (viewRange.end - viewRange.start) * 1.0
            let start = viewRange.start - interval
            let end = viewRange.end + interval
            queryActivity(start: start, end: end)
        }
    }
    
}