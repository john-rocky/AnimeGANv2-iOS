import UIKit
import AVFoundation

class AVPlayerView: UIView {
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    private var isVideoPlaying = false
    private var asset: AVAsset?
    private var timeObserverToken: Any?
    private var fadeOutTimer: Timer?

    // UI components
    private let playPauseButton = UIButton()
    private let seekSlider = UISlider()
    private let timeLabel = UILabel()
    let largeConfig = UIImage.SymbolConfiguration(pointSize: 60, weight: .bold, scale: .large)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPlayer()
        setupPlayPauseButton()
        setupSeekSlider()
        setupTimeLabel()
        setupTapGestureRecognizer()
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let timeObserverToken = timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }
    
    func play() {
        player?.play()
        isVideoPlaying = true
        hidePlayPauseButton()
    }
    
    func pause() {
        player?.pause()
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: largeConfig), for: .normal)
        isVideoPlaying = false
        showPlayPauseButton()
        fadeOutTimer?.invalidate()
    }
    

    private func setupPlayer() {
        playerLayer = AVPlayerLayer()
        playerLayer?.player = player
        layer.addSublayer(playerLayer!)
    }

    private func setupPlayPauseButton() {
        playPauseButton.setImage(UIImage(systemName: "play.fill",withConfiguration: largeConfig), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        addSubview(playPauseButton)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.isHidden = true
        playPauseButton.alpha = 0
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 100),
            playPauseButton.heightAnchor.constraint(equalToConstant: 100)
        ])
    }

    private func setupSeekSlider() {
        seekSlider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        seekSlider.isContinuous = true
        seekSlider.minimumTrackTintColor = .systemRed

        addSubview(seekSlider)
        seekSlider.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            seekSlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            seekSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            seekSlider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -60),
            seekSlider.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func setupTimeLabel() {
        timeLabel.font = UIFont.systemFont(ofSize: 14)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        addSubview(timeLabel)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            timeLabel.bottomAnchor.constraint(equalTo: seekSlider.topAnchor, constant: -10),
        ])
    }
    
    private func setupTapGestureRecognizer() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        self.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc private func viewTapped() {
        if isVideoPlaying {
            playPauseButton.setImage(UIImage(systemName: "pause.fill",withConfiguration: largeConfig), for: .normal)
            showPlayPauseButton()
            startFadeOutTimer()
        } else {
            play()
        }
    }

    private func showPlayPauseButton() {
        playPauseButton.isHidden = false
        self.playPauseButton.alpha = 1.0
    }

    private func hidePlayPauseButton() {
        UIView.animate(withDuration: 0.5, animations: {
            self.playPauseButton.alpha = 0
        }, completion: { finished in
            if finished {
                self.playPauseButton.isHidden = true
            }
        })
    }

    private func startFadeOutTimer() {
        fadeOutTimer?.invalidate()
        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hidePlayPauseButton()
        }
    }

    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func loadVideo(url: URL) {
        asset = AVAsset(url: url)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset!))
        playerLayer?.player = player
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            self?.updateSeekSlider(time)
            self?.updateTimeLabel()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(videoDidEnd), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
    }

    @objc private func togglePlayPause() {
        guard let player = player else { return }
        
        if isVideoPlaying {
            pause()
        } else {
            play()
        }
    }


    @objc private func videoDidEnd() {
        player?.seek(to: CMTime.zero)
        fadeOutTimer?.invalidate()
        pause()
    }

    @objc private func sliderValueChanged(_ sender: UISlider) {
        guard let duration = player?.currentItem?.duration else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        let value = Float64(seekSlider.value) * totalSeconds
        let seekTime = CMTime(value: Int64(value), timescale: 1)
        player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func updateSeekSlider(_ time: CMTime) {
        guard let duration = player?.currentItem?.duration else { return }
        let durationSeconds = CMTimeGetSeconds(duration)
        let currentTimeSeconds = CMTimeGetSeconds(time)

        if durationSeconds.isFinite && currentTimeSeconds.isFinite {
            seekSlider.value = Float(currentTimeSeconds / durationSeconds)
        }
    }
    
    private func updateTimeLabel() {
        guard let currentTime = player?.currentTime(),
              let duration = player?.currentItem?.duration else {
            timeLabel.text = "00:00 / 00:00"
            return
        }

        let currentTimeText = formatTimeForDisplay(currentTime)
        let durationText = formatTimeForDisplay(duration)
        timeLabel.text = "\(currentTimeText) / \(durationText)"
    }
    
    private func formatTimeForDisplay(_ time: CMTime) -> String {
        if !time.isValid || time.isIndefinite || time.isNegativeInfinity || time.isPositiveInfinity {
            return "00:00"
        }
        let totalSeconds = CMTimeGetSeconds(time)
        let hours = Int(totalSeconds / 3600)
        let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%02i:%02i:%02i", hours, minutes, seconds)
        } else {
            return String(format: "%02i:%02i", minutes, seconds)
        }
    }
}
