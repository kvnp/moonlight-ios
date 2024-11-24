//
//  OnScreenKey.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/8/4.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import UIKit


@objc class OnScreenButtonView: UIView, InstanceProviderDelegate {
    // receiving the OnScreenControls instance from delegate
    @objc func getOnScreenControlsInstance(_ sender: Any) {
        if let controls = sender as? OnScreenControls {
            self.onScreenControls = controls
            print("ClassA received OnScreenControls instance: \(controls)")
        } else {
            print("ClassA received an unknown sender")
        }
    }
    
    @objc static public var editMode: Bool = false
    @objc static public var timestampOfButtonBeingDragged: TimeInterval = 0
    @objc public var keyLabel: String
    @objc public var keyString: String
    @objc public var timestamp: TimeInterval
    @objc public var pressed: Bool
    @objc public var widthFactor: CGFloat
    @objc public var heightFactor: CGFloat
    @objc public var backgroundAlpha: CGFloat
    @objc public var latestMousePointerLocation: CGPoint
    @objc public var deltaX: CGFloat
    @objc public var deltaY: CGFloat
    
    private var onScreenControls: OnScreenControls
    private let label: UILabel
    // private let originalBackgroundColor: UIColor
    private var storedLocation: CGPoint = .zero
    private let minimumBorderAlpha: CGFloat = 0.19
    private var defaultBorderColor: CGColor = UIColor(white: 0.2, alpha: 0.3).cgColor
    private let borderLayer = CAShapeLayer()
    
    @objc init(keyString: String, keyLabel: String) {
        self.keyString = keyString
        self.keyLabel = keyLabel
        self.label = UILabel()
        // self.originalBackgroundColor = UIColor(white: 0.2, alpha: 0.7)
        self.timestamp = 0
        self.pressed = false
        self.widthFactor = 1.0
        self.heightFactor = 1.0
        self.backgroundAlpha = 0.5
        self.latestMousePointerLocation = CGPoint(x: 0, y: 0)
        self.deltaX = 0
        self.deltaY = 0
        self.onScreenControls = OnScreenControls()
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc public func setLocation(xOffset:CGFloat, yOffset:CGFloat) {
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: self.superview!.leadingAnchor, constant: xOffset),
            self.topAnchor.constraint(equalTo: self.superview!.topAnchor, constant: yOffset),
        ])
    }
    
    @objc public func enableRelocationMode(enabled: Bool){
        OnScreenButtonView.editMode = enabled
    }
    
    @objc public func adjustButtonTransparency(alpha: CGFloat){
        if(alpha != 0){
            self.backgroundAlpha = alpha
        }
        else{
            self.backgroundAlpha = 0.5
        }
        
        // setup default border from self.backgroundAlpha
        var borderAlpha = 1.15 * self.backgroundAlpha
        if(borderAlpha < minimumBorderAlpha){
            borderAlpha = minimumBorderAlpha
        }
        defaultBorderColor = UIColor(white: 0.2, alpha: borderAlpha).cgColor
        self.layer.borderColor = defaultBorderColor
        
        self.backgroundColor = UIColor(white: 0.2, alpha: self.backgroundAlpha - 0.18) // offset to be consistent with onScreen controller layer opacity
    }
    
    @objc public func resizeButtonView(){
        guard let superview = superview else { return }
        
        
        // Deactivate existing constraints if necessary
        NSLayoutConstraint.deactivate(self.constraints)
        
        // To resize the button, we must set this to false temporarily
        translatesAutoresizingMaskIntoConstraints = false
        
        
        // replace invalid factor values
        if(self.widthFactor == 0) {self.widthFactor = 1.0}
        if(self.heightFactor == 0) {self.heightFactor = 1.0}

        // Constraints for resizing
        let newWidthConstraint = self.widthAnchor.constraint(equalToConstant: 70 * self.widthFactor)
        let newHeightConstraint = self.heightAnchor.constraint(equalToConstant: 65 * self.heightFactor)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 70 * self.widthFactor),
            self.heightAnchor.constraint(equalToConstant: 65 * self.heightFactor),
        ])

        
        // Trigger layout update
        superview.layoutIfNeeded()
        
        // Re-setup buttonView style
        setupView()
        }
    
    
    
    @objc public func setupView() {
        label.text = self.keyLabel
        label.font = UIFont.boldSystemFont(ofSize: 19)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.1  // Adjust the scale factor as needed
        
        label.textColor = UIColor(white: 1.0, alpha: 0.82)
        label.textAlignment = .center
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 1, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false // enable auto alignment for the label
        
        self.translatesAutoresizingMaskIntoConstraints = true // this is mandatory to prevent unexpected key view location change
        
        // reset to default border
        self.layer.borderWidth = 1
        var borderAlpha = 1.15 * self.backgroundAlpha
        if(borderAlpha < minimumBorderAlpha){
            borderAlpha = minimumBorderAlpha
        }
        defaultBorderColor = UIColor(white: 0.2, alpha: borderAlpha).cgColor
        self.borderLayer.borderColor = defaultBorderColor
        
        self.layer.cornerRadius = 15
        self.backgroundColor = UIColor(white: 0.2, alpha: self.backgroundAlpha - 0.18) // offset to be consistent with OSC opacity
        // self.layer.shadowColor = UIColor.clear.cgColor
        // self.layer.shadowRadius = 8
        // self.layer.shadowOpacity = 0.5
        
        addSubview(label)
        
        NSLayoutConstraint.activate([
            //self.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.088),
            //self.heightAnchor.constraint(equalToConstant: UIScreen.main.bounds.height * 0.1),
            self.widthAnchor.constraint(equalToConstant: 70 * self.widthFactor),
            self.heightAnchor.constraint(equalToConstant: 65 * self.widthFactor),
        ])
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10), // set up label size contrain within UIView
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            //label.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        setupBorderLayer();
    }
    
    private func buttonDownVisualEffect() {
        // setupBorderLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // self.layer.borderWidth = 0
        borderLayer.borderWidth = 8.6
        borderLayer.borderColor = UIColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 0.86).cgColor
        CATransaction.commit()
    }
    
    private func buttonUpVisualEffect() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // self.layer.borderWidth = 1
        borderLayer.borderWidth = 0
        borderLayer.borderColor = defaultBorderColor
        CATransaction.commit()
    }
    

    private func setupBorderLayer() {
        // Create a shape layer for the border
        
        // Set the frame to be larger than the view to expand outward
        borderLayer.borderWidth = 0
        borderLayer.frame = self.bounds.insetBy(dx: -8.6, dy: -8.6) // Adjust the inset as needed
        borderLayer.cornerRadius = self.layer.cornerRadius + 8.6
        borderLayer.backgroundColor = UIColor.clear.cgColor;
        borderLayer.fillColor = UIColor.clear.cgColor;
        
        // Create a path for the border
        let path = UIBezierPath(roundedRect: borderLayer.bounds, cornerRadius: borderLayer.cornerRadius)
        borderLayer.path = path.cgPath
        
        // Add the border layer below the main view layer
        self.layer.superlayer?.insertSublayer(borderLayer, below: self.layer)
        
        // Retrieve the current frame to account for transformations, this will update the coords for new position CGPointMake
        borderLayer.position = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame))
    }

    
    
    // Touch event handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // print("touchDown: %f", CACurrentMediaTime())
        
        if(touches.count == 1){
            self.latestMousePointerLocation = (touches.first?.location(in: self))!
        }
        
        self.pressed = true
        super.touchesBegan(touches, with: event)
        //self.backgroundColor = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.7)
        
        OnScreenControls.testMethod();
        // RelativeTouchHandler.testMethod();
        
        if !OnScreenButtonView.editMode {
            // self.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
            self.buttonDownVisualEffect()
            // if the command(keystring contains "+", it's a multi-key command or a quick triggering key, rather than a physical button
            if(self.keyString.contains("+")){
                let keyboardCmdStrings = CommandManager.shared.extractKeyStrings(from: self.keyString)!
                CommandManager.shared.sendKeyDownEventWithDelay(keyboardCmdStrings: keyboardCmdStrings) // send multi-key command
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { // reset shadow color immediately 50ms later
                    self.buttonUpVisualEffect()
                }
            }
            // if there's no "+" in the keystring, treat it as a regular button:
            else{
                if(CommandManager.mouseButtonMappings.keys.contains(self.keyString)){
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(CommandManager.mouseButtonMappings[self.keyString]!))
                }
                else{
                    LiSendKeyboardEvent(CommandManager.keyMappings[self.keyString]!,Int8(KEY_ACTION_DOWN), 0)
                }
            }
        }
        // here is in edit mode:
        else{
            NotificationCenter.default.post(name: Notification.Name("OnScreenButtonViewSelected"),object: self) // inform layout tool controller to fetch button size factors. self will be passed as the object of the notification
            if let touch = touches.first {
                let touchLocation = touch.location(in: superview)
                storedLocation = touchLocation
            }
        }

    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        OnScreenButtonView.timestampOfButtonBeingDragged = self.timestamp
        
        // Move the buttonView based on touch movement in relocation mode
        if OnScreenButtonView.editMode {
            if let touch = touches.first {
                let currentLocation = touch.location(in: superview)
                let offsetX = currentLocation.x - storedLocation.x
                let offsetY = currentLocation.y - storedLocation.y
                
                center = CGPoint(x: center.x + offsetX, y: center.y + offsetY)
                //NSLog("x coord: %f, y coord: %f", self.frame.origin.x, self.frame.origin.y)
                storedLocation = currentLocation // Update initial center for next movement
            }
        }
        else{
            if touches.count == 1 && false{
                let currentLocation: CGPoint = (touches.first?.location(in: self))!
                deltaX = currentLocation.x - self.latestMousePointerLocation.x
                deltaY = currentLocation.y - self.latestMousePointerLocation.y
                // NSLog("coord test deltaX: %f, deltaY: %f", deltaX, deltaY)
                self.onScreenControls.sendLeftStickTouchPadEvent(withDeltaX: deltaX, deltaY: deltaY);
            }
        }
    }
    
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // self.pressed = false // will be reset outside the class
        super.touchesEnded(touches, with: event)
        if !OnScreenButtonView.editMode && touches.count == 1 {
            self.onScreenControls.clearLeftStickTouchPadFlag();
        }
        if !OnScreenButtonView.editMode && !self.keyString.contains("+") { // if the command(keystring contains "+", it's a multi-key command rather than a single key button
            
            if(CommandManager.mouseButtonMappings.keys.contains(self.keyString)){
                LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(CommandManager.mouseButtonMappings[self.keyString]!))
            }
            else{
                LiSendKeyboardEvent(CommandManager.keyMappings[self.keyString]!,Int8(KEY_ACTION_UP), 0)
            }
            self.buttonUpVisualEffect()
            return;
        }
        // self.backgroundColor = self.originalBackgroundColor
        // self.layer.shadowColor = UIColor.clear.cgColor
        // self.layer.borderWidth = 1

        guard let superview = superview else { return }

        // Deactivate existing constraints if necessary
        NSLayoutConstraint.deactivate(self.constraints)

        // Add new constraints based on the current center position
        translatesAutoresizingMaskIntoConstraints = true
                
        // Create new constraints
        let newLeadingConstraint = self.leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: self.frame.origin.x)
        let newTopConstraint = self.topAnchor.constraint(equalTo: superview.topAnchor, constant: self.frame.origin.y)
    
        // Activate the new location constraints
        NSLayoutConstraint.activate([newLeadingConstraint, newTopConstraint])

        // Trigger layout update
        superview.layoutIfNeeded()

        setupView(); //re-setup buttonView style
    }
}
