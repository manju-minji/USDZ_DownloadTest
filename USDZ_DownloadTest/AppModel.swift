//
//  AppModel.swift
//  USDZ_DownloadTest
//
//  Created by LeeMinJi on 11/17/25.
//

import SwiftUI

/// Maintains app-wide state
/// 앱 전역 상태를 관리합니다.
@MainActor
@Observable
class AppModel {
    // MARK: - Types

    /// Represents the state of the immersive space lifecycle.
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
    }

    /// Represents the overall download state for the USDZ assets.
    enum DownloadState {
        case idle
        case running
        case completed
        case failed(Error)
    }

    // MARK: - Constants

    /// Identifier of the immersive space.
    let immersiveSpaceID = "ImmersiveSpace"

    // MARK: - Public (Observable) State

    /// Current state of immersive space.
    var immersiveSpaceState: ImmersiveSpaceState = .closed

    /// Current download state.
    private(set) var downloadState: DownloadState = .idle

    /// Indicates whether any download task is currently running.
    private(set) var isDownloading: Bool = false

    /// Last occurred error during download, if any.
    private(set) var lastError: Error? = nil

    // MARK: - Dependencies

    /// Manager responsible for downloading USDZ files.
    private(set) var usdzDownloadManager: USDZDownloadManager

    // MARK: - Tasks (Cancellation Support)

    /// A handle for the currently running download task to support cancellation.
    private var currentDownloadTask: Task<Void, Never>? = nil

    // MARK: - Configuration

    /// Default set of USDZ URLs.
    static let defaultUSDZURLs: [String] = [
        "https://developer.apple.com/augmented-reality/quick-look/models/drummertoy/toy_drummer.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/stratocaster/fender_stratocaster.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/baseball-glove/glove_baseball_mtl_variant.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/chameleon/chameleon_anim_mtl_variant.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/pancakes/pancakes_photogrammetry.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/hummingbird/hummingbird_anim.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/toycar/toy_car.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/robot.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/football/ball_football_realistic.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/baseball/ball_baseball_realistic.usdz",
        "https://developer.apple.com/augmented-reality/quick-look/models/boxing-glove/boxing_glove_realistic.usdz"
    ]

    // MARK: - Init

    /// Initialize AppModel with a provided download manager (designated initializer).
    init(usdzDownloadManager: USDZDownloadManager) {
        self.usdzDownloadManager = usdzDownloadManager
    }

    /// Convenience initializer that constructs the default download manager on the main actor.
    convenience init() {
        self.init(usdzDownloadManager: USDZDownloadManager(urls: AppModel.defaultUSDZURLs))
    }

    // MARK: - Public API

    /// Starts all downloads concurrently without limiting concurrency.
    /// 동시성 제한 없이 모든 파일을 동시에 다운로드합니다.
    func downloadAllConcurrently() {
        startDownloadTask {
            await self.usdzDownloadManager.startDownloadingAll()
            await MainActor.run { self.downloadState = .completed }
        }
    }

    /// Starts all downloads but limits maximum concurrent tasks.
    /// 최대 동시 다운로드 수를 제한하여 다운로드합니다.
    /// - Parameter maxConcurrent: Maximum number of concurrent downloads.
    func downloadAllWithLimit(maxConcurrent: Int = 3) {
        startDownloadTask {
            await self.usdzDownloadManager.startDownloadingAllWithLimit(maxConcurrentDownloads: maxConcurrent)
            await MainActor.run { self.downloadState = .completed }
        }
    }

    /// Cancels any ongoing download tasks.
    /// 진행 중인 다운로드 작업을 취소합니다.
    func cancelDownloads() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        isDownloading = false
        downloadState = .idle
    }

    // MARK: - Immersive Space State Transitions

    /// Sets immersive space to inTransition.
    func beginImmersiveTransition() {
        immersiveSpaceState = .inTransition
    }

    /// Marks immersive space as open.
    func markImmersiveOpen() {
        immersiveSpaceState = .open
    }

    /// Marks immersive space as closed.
    func markImmersiveClosed() {
        immersiveSpaceState = .closed
    }

    // MARK: - Helpers

    /// Wraps a download async operation into a cancellable Task and manages common state updates.
    private func startDownloadTask(_ operation: @escaping @Sendable () async throws -> Void) {
        // Cancel any previous task first.
        currentDownloadTask?.cancel()

        isDownloading = true
        lastError = nil
        downloadState = .running

        currentDownloadTask = Task {
            defer {
                Task { @MainActor in
                    self.isDownloading = false
                    self.currentDownloadTask = nil
                }
            }
            if Task.isCancelled { return }
            do {
                try await operation()
            } catch is CancellationError {
                await MainActor.run { self.downloadState = .idle }
            } catch {
                await MainActor.run {
                    self.lastError = error
                    self.downloadState = .failed(error)
                }
            }
        }
    }
}
