//
//  ActiveCallViewController.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 29/01/2023.
//

import Foundation
import UIKit
import Combine


class ActiveCallViewModel: ObservableObject {
    @Published var call: Call
    @Published var activeCalls: Dictionary<CallId,Call> = [:]

    private var cancellables = Set<AnyCancellable>()
    
    init(for call:Call, all_calls:some Publisher<Dictionary<CallId,Call>, Never>){
        self.call = call
        
        all_calls
            .assign(to: \.activeCalls, on:self)
            .store(in: &self.cancellables)
        
        // keep call updated
        all_calls
            .map { m in m[self.call.id]}
            .compactMap { $0 }
            .assign(to: \.call, on:self)
            .store(in: &cancellables)
    }
}

class ActiveCallViewController: UIViewController {
    var calleeLabel: UILabel!
    var callStatusLabel: UILabel!
    var callStatusVisual: UIView!
    var callStatusVisualTop: UIView!


    var hangupButton: UIButton!
    var muteButton: UIButton!
    var cancels = Set<AnyCancellable>()

    var viewModel:ActiveCallViewModel? {
        didSet(value) {
            if (self.isViewLoaded) { bind()}
        }
    }
    
    func isBound() -> Bool {
        return !cancels.isEmpty
    }
    
    func bind() {
        guard let viewModel else {
            return
        }
        _ = cancels.map { $0.cancel() }
        self.callStatusVisual.layer.removeAnimation(forKey: "ringing")
        self.callStatusVisual.layer.removeAnimation(forKey: "answer")
        self.callStatusVisualTop.layer.removeAnimation(forKey: "rejected")
        
        viewModel.$call.map { $0.to }.sink(receiveValue: { s in
            self.calleeLabel.text = s
        })
        .store(in: &cancels)
        
        viewModel.$call
            .map { $0.status }
            // deduplicate just incase...
            .scan((state:.unknown, didChange:false)){ current, new in (new , current.0 != new) }.filter { $0.1 }.map {$0.0}
            .sink(receiveValue: { s in
            switch(s) {
            case .ringing:
                self.callStatusVisual.backgroundColor = .systemGray
                self.callStatusVisualTop.backgroundColor = .black
                self.callStatusVisual.layer.add(ActiveCallViewController.RingingAnimation, forKey: "ringing")
                self.callStatusLabel.text = "ringing"
            case .answered:
                self.callStatusVisual.layer.removeAnimation(forKey: "ringing")
                self.callStatusVisual.layer.add(ActiveCallViewController.answerAnimation, forKey: "answer")
                self.callStatusVisual.backgroundColor = .systemGreen
                self.callStatusVisualTop.backgroundColor = .systemGreen
                self.callStatusLabel.text = "answered"
            case .rejected:
                self.clearAnimation()
                self.callStatusVisualTop.layer.add(ActiveCallViewController.RejectedAnimation, forKey: "rejected")
                self.callStatusLabel.text = "rejected"
                self.callStatusVisual.backgroundColor = .systemBackground
                self.callStatusVisualTop.backgroundColor = .red
                self.eventuallyDismiss()

            case .completed, .canceled, .unknown:
                self.clearAnimation()
                self.callStatusVisual.backgroundColor = .systemGray
                self.callStatusVisualTop.backgroundColor = .systemGray
                self.callStatusLabel.text = "complete"
                self.eventuallyDismiss()

            }
        })
        .store(in: &cancels)
    }
    
    func clearAnimation() {
        CATransaction.begin()
        self.callStatusVisual.layer.removeAnimation(forKey: "answer")
        self.callStatusVisual.layer.removeAnimation(forKey: "ringing")
        self.callStatusVisualTop.layer.removeAnimation(forKey: "rejected")
        CATransaction.commit()
    }
    
    func eventuallyDismiss() {
        Timer.publish(every: 1, on: RunLoop.main, in: .default).autoconnect().first().sink {  _ in
            if self.navigationController?.topViewController == self{
                self.navigationController?.popViewController(animated: true)
            }
        }.store(in: &self.cancels)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if (!self.isBound()){
            bind()
        }
    }
    
    override func loadView() {
        super.loadView()
        view = UIView()
        view.backgroundColor = .systemBackground
        
        calleeLabel = UILabel()
        calleeLabel.textAlignment = .center
        calleeLabel.font = UIFont.preferredFont(forTextStyle: .title1)

        
        callStatusLabel = UILabel()
        calleeLabel.textAlignment = .center
        callStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        callStatusVisual = UICustomRingView()
        callStatusVisual.backgroundColor = .systemGray2
        
        callStatusVisualTop = UICustomRingView()
        callStatusVisualTop.backgroundColor = .black
        
        let callStatusVisualParent = UIView()
        callStatusVisualParent.translatesAutoresizingMaskIntoConstraints = false
        callStatusVisualParent.addSubview(callStatusVisual)
        callStatusVisualParent.addSubview(callStatusVisualTop)
        callStatusVisualParent.addSubview(callStatusLabel)

        
        let callStatusVisualSize = 250.0
//
        let callVisualConstraints = [
            callStatusVisual.heightAnchor.constraint(equalToConstant: callStatusVisualSize),
            callStatusVisual.widthAnchor.constraint(equalToConstant: callStatusVisualSize),
            callStatusVisual.centerXAnchor.constraint(equalTo: callStatusVisualParent.centerXAnchor),
            callStatusVisual.centerYAnchor.constraint(equalTo: callStatusVisualParent.centerYAnchor),
            
            callStatusVisualTop.heightAnchor.constraint(equalToConstant: callStatusVisualSize),
            callStatusVisualTop.widthAnchor.constraint(equalToConstant: callStatusVisualSize),
            callStatusVisualTop.centerXAnchor.constraint(equalTo: callStatusVisualParent.centerXAnchor),
            callStatusVisualTop.centerYAnchor.constraint(equalTo: callStatusVisualParent.centerYAnchor),

            callStatusLabel.centerXAnchor.constraint(equalTo: callStatusVisualParent.centerXAnchor),
            callStatusLabel.centerYAnchor.constraint(equalTo: callStatusVisualParent.centerYAnchor)
        ]
        
        hangupButton = UIButton()
        hangupButton.translatesAutoresizingMaskIntoConstraints = false
        hangupButton.setTitle("X", for: .normal)
        hangupButton.backgroundColor = .systemRed
        hangupButton.addTarget(self, action: #selector(hangupButtonPressed), for: .touchUpInside)
        
        muteButton = UIButton()
        muteButton.backgroundColor = UIColor.systemGray
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.setTitle("X", for: .normal)
        muteButton.addTarget(self, action: #selector(hangupButtonPressed), for: .touchUpInside)
        
        let callControlStack = UIStackView()
        callControlStack.axis = .horizontal
        callControlStack.distribution = .equalCentering
        callControlStack.alignment = .center
        callControlStack.addArrangedSubview(muteButton)
        callControlStack.addArrangedSubview(hangupButton)

        let callControlButtonSize = 75.0
        let callControlConstraints = [
            hangupButton.heightAnchor.constraint(equalToConstant: callControlButtonSize),
            hangupButton.widthAnchor.constraint(equalToConstant: callControlButtonSize),
            muteButton.heightAnchor.constraint(equalToConstant: callControlButtonSize),
            muteButton.widthAnchor.constraint(equalToConstant: callControlButtonSize),
        ]
        
        muteButton.layer.cornerRadius = callControlButtonSize * 0.5
        hangupButton.layer.cornerRadius = callControlButtonSize * 0.5
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .equalCentering
        stackView.alignment = .fill
        stackView.addArrangedSubview(calleeLabel)
        stackView.addArrangedSubview(callStatusVisualParent)
        stackView.addArrangedSubview(callControlStack)
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate(callVisualConstraints + callControlConstraints + [
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -25)
        ])

        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Set once we know layout sizing
//        callStatusVisual.layer.cornerRadius = callStatusVisual.bounds.size.width * 0.5
//        callStatusVisual.subviews[0].layer.cornerRadius =  callStatusVisual.bounds.size.width * 0.85 * 0.5
//        callStatusVisualInner2.layer.cornerRadius =  callStatusVisual.bounds.size.width * 0.65 * 0.5
    }
    
    @objc func hangupButtonPressed(_ sender:UIButton) {
        viewModel?.call.ref.hangup { _ in }
    }
}

class UICustomRingView: UIView {
    
    private let inner: UIView = UIView()
    var ringWidth: CGFloat = 0.85
    var ringSize: CGFloat = 250
    
    override init(frame: CGRect) {
      super.init(frame: frame)
      setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
      super.init(coder: aDecoder)
      setupView()
    }
    
    private func setupView() {
        inner.backgroundColor = .systemBackground
        self.translatesAutoresizingMaskIntoConstraints = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        setupLayout()
    }
    
    override var intrinsicContentSize: CGSize {
      return CGSize(width: ringSize, height: ringSize)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.size.width * 0.5
        inner.layer.cornerRadius = bounds.size.width * ringWidth * 0.5
    }
    
    private func setupLayout() {
        self.addConstraints([
            inner.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: ringWidth),
            inner.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: ringWidth),

            inner.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
        self.setNeedsUpdateConstraints()
    }
    
    override class var requiresConstraintBasedLayout: Bool {
        return true
    }
}


fileprivate extension ActiveCallViewController{
    
    static let RingingAnimation: CAAnimation = { () -> CAAnimation in
        var anim = [CABasicAnimation]()
        let transformAnim = CABasicAnimation(keyPath: "transform.scale")
        transformAnim.duration = 2.0
        transformAnim.repeatCount = 200
        transformAnim.fromValue = 0.0
        transformAnim.toValue = 5.0
        transformAnim.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        anim.append(transformAnim)

        let alphaAnim = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        alphaAnim.duration = 2.0
        alphaAnim.repeatCount = 200
        alphaAnim.fromValue = [1.0]
        alphaAnim.toValue = [0.0]
        alphaAnim.fillMode = .forwards
        transformAnim.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)

        anim.append(alphaAnim)
        
        let group = CAAnimationGroup()
//        group.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        group.animations = anim
        group.duration = 10.0
        group.repeatCount = 200
        
        return group
    }()
    
    
    static let answerAnimation: CAAnimation = { () -> CAAnimation in
        var anim = [CAAnimation]()
        let transformAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        transformAnim.duration = 2
        transformAnim.repeatCount = 200
        transformAnim.values = [1.0, 1.1, 1.0]
        transformAnim.keyTimes = [0, 0.333, 1]
        transformAnim.timingFunctions = [
            CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut),
            CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        ]
        anim.append(transformAnim)
        
        let group = CAAnimationGroup()
        group.animations = anim
        group.duration = 4
        group.repeatCount = 200
        
        return group
    }()
    
    
    static let RejectedAnimation: CAAnimation = { () -> CAAnimation in
        var anim = [CABasicAnimation]()

        let alphaAnim = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        alphaAnim.duration = 0.5
        alphaAnim.repeatCount = 4
        alphaAnim.fromValue = [1.0]
        alphaAnim.toValue = [0.0]
        alphaAnim.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        anim.append(alphaAnim)
        
        let group = CAAnimationGroup()
        group.animations = anim
        group.duration = 2
        group.repeatCount = 1
        
        return group
    }()
    
    
}
