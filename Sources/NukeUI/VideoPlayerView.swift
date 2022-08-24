// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import AVKit
import Foundation

#if !os(watchOS)

@MainActor
public final class VideoPlayerView: _PlatformBaseView {
    // MARK: Configuration

    /// `.resizeAspectFill` by default.
    public var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            _playerLayer?.videoGravity = videoGravity
        }
    }

    /// `true` by default. If disabled, will only play a video once.
    public var isLooping = true {
        didSet {
            guard isLooping != oldValue else { return }
            player?.actionAtItemEnd = isLooping ? .none : .pause
            if isLooping, !(player?.nowPlaying ?? false) {
                restart()
            }
        }
    }

    /// Add if you want to do something at the end of the video
    var onVideoFinished: (() -> Void)?

    // MARK: Initialization

    public var playerLayer: AVPlayerLayer {
        if let layer = _playerLayer {
            return layer
        }
        let playerLayer = AVPlayerLayer()
#if os(macOS)
        wantsLayer = true
        self.layer?.addSublayer(playerLayer)
#else
        self.layer.addSublayer(playerLayer)
#endif
        playerLayer.frame = bounds
        playerLayer.videoGravity = videoGravity
        _playerLayer = playerLayer
        return playerLayer
    }

    private var _playerLayer: AVPlayerLayer?

    #if os(iOS) || os(tvOS)
    override public func layoutSubviews() {
        super.layoutSubviews()

        _playerLayer?.frame = bounds
    }
    #elseif os(macOS)
    override public func layout() {
        super.layout()

        _playerLayer?.frame = bounds
    }
#endif

    // MARK: Private

    public var player: AVPlayer? {
        didSet {
            registerNotifications()
            player?.allowsExternalPlayback = false
        }
    }

    private var playerObserver: AnyObject?

    public func reset() {
        _playerLayer?.player = nil
        player = nil
        playerObserver = nil
    }

    public var asset: AVAsset? {
        didSet { assetDidChange() }
    }

    private func assetDidChange() {
        if asset == nil {
            reset()
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTimeNotification(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )

#if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
#endif
    }

    public func restart() {
            player?.seek(to: CMTime.zero)
            player?.play()
    }

    public func play() {
        guard let asset = asset else {
            return
        }
        
        let track = asset.loadTracks(withMediaType: .video) { assetTracks, error in
            guard let asset_ = assetTracks?.first else { return }
            let composition = AVMutableComposition()
            let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            try! compositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset_, at: .zero)
            
            let playerItem = AVPlayerItem(asset: composition)
            let player = AVQueuePlayer(playerItem: playerItem)
            player.isMuted = true
            
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.actionAtItemEnd = self.isLooping ? .none : .pause
            player.allowsExternalPlayback = false
            
            self.player = player
            
            self.playerLayer.player = player
            
            self.playerObserver = player.observe(\.status, options: [.new, .initial]) { player, _ in
                Task { @MainActor in
                    if player.status == .readyToPlay {
                        player.play()
                    }
                }
            }
        }
    }
    
    @objc private func playerItemDidPlayToEndTimeNotification(_ notification: Notification) {
        guard let playerItem = notification.object as? AVPlayerItem else {
            return
        }
        if isLooping {
            playerItem.seek(to: CMTime.zero, completionHandler: nil)
        } else {
            onVideoFinished?()
        }
    }

    @objc private func applicationWillEnterForeground() {
        if shouldResumeOnInterruption {
            player?.play()
        }
    }

#if os(iOS) || os(tvOS)
    override public func willMove(toWindow newWindow: UIWindow?) {
        if newWindow != nil && shouldResumeOnInterruption {
            player?.play()
        }
    }
#endif

    private var shouldResumeOnInterruption: Bool {
        return player?.nowPlaying == false &&
        player?.status == .readyToPlay &&
        isLooping
    }
}

extension AVLayerVideoGravity {
    init(_ contentMode: ImageResizingMode) {
        switch contentMode {
        case .fill: self = .resize
        case .aspectFill: self = .resizeAspectFill
        default: self = .resizeAspect
        }
    }
}

@MainActor
extension AVPlayer {
    var nowPlaying: Bool {
        rate != 0 && error == nil
    }
}

#endif
