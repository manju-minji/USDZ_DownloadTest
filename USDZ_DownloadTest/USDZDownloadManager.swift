//
//  USDZDownloadManager.swift
//  USDZ_DownloadTest
//
//  Created by LeeMinJi on 11/17/25.
//

import SwiftUI
import RealityKit
import Foundation

struct USDZFileInfo: Identifiable, Equatable {
    let id = UUID()
    let url: String
    var fileName: String {
        URL(string: url)?.lastPathComponent ?? "Unknown"
    }
    var downloadStartTime: Date?
    var downloadEndTime: Date?
    var renderStartTime: Date?
    var renderEndTime: Date?
    var fileSize: Int64 = 0
    var isDownloaded: Bool = false
    var isRendered: Bool = false
    var isDownloading: Bool = false
    var entity: Entity?
    var error: String?
    
    var downloadDuration: TimeInterval? {
        guard let start = downloadStartTime, let end = downloadEndTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var renderDuration: TimeInterval? {
        guard let start = renderStartTime, let end = renderEndTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

@MainActor
@Observable
class USDZDownloadManager {
    private(set) var files: [USDZFileInfo] = []
    private let urlSession = URLSession.shared
    private(set) var currentActiveDownloads: Int = 0
    
    // 전체 다운로드 시간 추적
    private(set) var totalDownloadStartTime: Date?
    private(set) var totalDownloadEndTime: Date?
    private(set) var isDownloadingAll: Bool = false
    
    init(urls: [String]) {
        self.files = urls.map { USDZFileInfo(url: $0) }
    }
    
    /// 전체 다운로드 소요 시간 (초)
    var totalDownloadDuration: TimeInterval? {
        guard let start = totalDownloadStartTime, let end = totalDownloadEndTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    /// 전체 다운로드 소요 시간을 포맷된 문자열로 반환
    var totalDownloadDurationFormatted: String {
        guard let duration = totalDownloadDuration else { return "측정되지 않음" }
        return String(format: "%.2f초", duration)
    }
    
    /// 다운로드 완료된 파일 수
    var completedDownloadsCount: Int {
        files.filter { $0.isDownloaded || $0.error != nil }.count
    }
    
    /// 전체 파일 수
    var totalFilesCount: Int {
        files.count
    }
    
    /// 다운로드 진행률 (0.0 ~ 1.0)
    var downloadProgress: Double {
        guard totalFilesCount > 0 else { return 0.0 }
        return Double(completedDownloadsCount) / Double(totalFilesCount)
    }
    
    func startDownloadingAll() async {
        // 전체 다운로드 시작 시간 기록
        totalDownloadStartTime = Date()
        totalDownloadEndTime = nil
        isDownloadingAll = true
        
        // 모든 파일 상태 초기화
        resetAllFileStates()
        currentActiveDownloads = 0
        
        // 동시 다운로드를 위해 TaskGroup 사용
        await withTaskGroup(of: Void.self) { taskGroup in
            for index in files.indices {
                taskGroup.addTask {
                    await self.downloadFile(at: index)
                }
            }
        }
        
        // 전체 다운로드 완료 시간 기록
        totalDownloadEndTime = Date()
        isDownloadingAll = false
        
        // 모든 다운로드가 완료되었음을 notification으로 알림
        NotificationCenter.default.post(name: .allUsdzFilesDownloadComplete, object: nil)
        print("📢 Posted notification: All USDZ files download complete")
    }
    
    /// 최대 동시 다운로드 수를 제한하는 버전
    func startDownloadingAllWithLimit(maxConcurrentDownloads: Int = 3) async {
        // 전체 다운로드 시작 시간 기록
        totalDownloadStartTime = Date()
        totalDownloadEndTime = nil
        isDownloadingAll = true
        
        // 모든 파일 상태 초기화
        resetAllFileStates()
        currentActiveDownloads = 0
        
        let indices = Array(files.indices)
        
        await withTaskGroup(of: Void.self) { taskGroup in
            var currentIndex = 0
            
            // 초기 작업들을 시작 (최대 동시 다운로드 수만큼)
            for _ in 0..<min(maxConcurrentDownloads, indices.count) {
                if currentIndex < indices.count {
                    let index = indices[currentIndex]
                    taskGroup.addTask {
                        await self.downloadFile(at: index)
                    }
                    currentIndex += 1
                }
            }
            
            // 작업이 완료될 때마다 새로운 작업 추가
            while let _ = await taskGroup.next() {
                if currentIndex < indices.count {
                    let index = indices[currentIndex]
                    taskGroup.addTask {
                        await self.downloadFile(at: index)
                    }
                    currentIndex += 1
                }
            }
        }
        
        // 전체 다운로드 완료 시간 기록
        totalDownloadEndTime = Date()
        isDownloadingAll = false
        
        // 모든 다운로드가 완료되었음을 notification으로 알림
        NotificationCenter.default.post(name: .allUsdzFilesDownloadComplete, object: nil)
        print("📢 Posted notification: All USDZ files download complete (with limit)")
    }

    // MARK: - Migration Note
    // 기존 startDownloadingSequentially()는 제거되었습니다.
    // 순차 다운로드가 필요하면 아래 둘 중 하나를 사용하세요.
    // 1) await startDownloadingSequentiallyViaLimit()
    // 2) await startDownloadingAllWithLimit(maxConcurrentDownloads: 1)
    
    private func downloadFile(at index: Int) async {
        guard index < files.count else { return }
        
        files[index].isDownloading = true
        files[index].downloadStartTime = Date()
        await MainActor.run { self.currentActiveDownloads += 1 }
        
        do {
            guard let url = URL(string: files[index].url) else {
                files[index].error = "Invalid URL"
                files[index].isDownloading = false
                await MainActor.run { self.currentActiveDownloads = max(0, self.currentActiveDownloads - 1) }
                return
            }
            
            let (data, response) = try await urlSession.data(from: url)
            
            files[index].downloadEndTime = Date()
            files[index].fileSize = Int64(data.count)
            files[index].isDownloaded = true
            files[index].isDownloading = false
            await MainActor.run { self.currentActiveDownloads = max(0, self.currentActiveDownloads - 1) }
            
            // Create entity from downloaded data
            await createEntity(from: data, at: index)
            
        } catch {
            files[index].error = error.localizedDescription
            files[index].downloadEndTime = Date()
            files[index].isDownloading = false
            await MainActor.run { self.currentActiveDownloads = max(0, self.currentActiveDownloads - 1) }
        }
    }
    
    private func createEntity(from data: Data, at index: Int) async {
        files[index].renderStartTime = Date()
        
        do {
            // Create temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_\(index).usdz")
            try data.write(to: tempURL)
            
            // Load entity from temporary file
            let entity = try await Entity(contentsOf: tempURL)
            files[index].entity = entity
            files[index].isRendered = true
            files[index].renderEndTime = Date()
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
            
            // 파일이 준비되었음을 notification으로 알림
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .usdzFileReady,
                    object: nil,
                    userInfo: [
                        NotificationUserInfoKey.fileInfo: files[index],
                        NotificationUserInfoKey.fileIndex: index
                    ]
                )
                print("📢 Posted notification for file \(index): \(files[index].fileName)")
            }
            
        } catch {
            files[index].error = error.localizedDescription
            files[index].renderEndTime = Date()
            
            // 에러가 발생해도 notification을 발송 (에러 정보 포함)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .usdzFileReady,
                    object: nil,
                    userInfo: [
                        NotificationUserInfoKey.fileInfo: files[index],
                        NotificationUserInfoKey.fileIndex: index
                    ]
                )
                print("📢 Posted notification for file \(index) with error: \(error.localizedDescription)")
            }
        }
    }
    
    func getRenderedEntities() -> [Entity] {
        return files.compactMap { $0.entity }
    }
    
    /// 모든 파일의 다운로드 상태를 초기화
    private func resetAllFileStates() {
        for index in files.indices {
            files[index].downloadStartTime = nil
            files[index].downloadEndTime = nil
            files[index].renderStartTime = nil
            files[index].renderEndTime = nil
            files[index].fileSize = 0
            files[index].isDownloaded = false
            files[index].isRendered = false
            files[index].isDownloading = false
            files[index].entity = nil
            files[index].error = nil
        }
    }
}

