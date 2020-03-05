//
//  QRCode.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 03.03.20.
//

import Gtk
import Cairo

import CQREncode

class QRCode: DrawingArea {
    init() {
        super.init(DrawingAreaRef().drawing_area_ptr)
        
        onDraw { _, cr in
            self.drawQRCode(cr)
            return false
        }
    }
    
    convenience init(data: String) {
        self.init()
        self.data = data
        updateQRCode()
    }
    
    var data: String? {
        didSet {
            updateQRCode()
        }
    }
    
    private var qrData: UnsafeMutablePointer<QRcode>?
    
    func updateQRCode() {
        if(qrData != nil) {
            QRcode_free(qrData)
        }
        
        qrData = QRcode_encodeString(data, 0, QR_ECLEVEL_M, QR_MODE_8, 1)
        
        self.queueDraw()
    }
    
    func drawQRCode(_ cr: cairo.ContextProtocol) {
        if let qrData = qrData {
            let rowLength = qrData.pointee.width
            let data = qrData.pointee.data!
            
            let width = min(self.allocatedWidth, self.allocatedHeight)
            let xOffset = Double(self.allocatedWidth - width) / 2
            let yOffset = Double(self.allocatedHeight - width) / 2
            let pixelWidth = Double(width) / Double(rowLength)
            
            cr.setSource(red: 0, green: 0, blue: 0)
            
            for y in 0..<rowLength {
                for x in 0..<rowLength {
                    // Check least significant bit
                    if data[Int(y * rowLength + x)] & UInt8(1) == 1 {
                        cr.rectangle(
                            x: xOffset + Double(x) * pixelWidth - 0.5,
                            y: yOffset + Double(y) * pixelWidth - 0.5,
                            width: pixelWidth + 0.5,
                            height: pixelWidth + 0.5
                        )
                        cr.fill()
                    }
                }
            }
        }
    }
    
    deinit {
        if(qrData != nil) {
            QRcode_free(qrData)
        }
    }
}
