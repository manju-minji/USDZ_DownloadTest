//
//  USDZDownloadManager.swift
//  USDZ_DownloadTest
//
//  Created by LeeMinJi on 11/17/25.
//

import SwiftUI
import RealityKit
import Foundation
import Network

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
    private let urlSession: URLSession
    private(set) var currentActiveDownloads: Int = 0
    
    // 전체 다운로드 시간 추적
    private(set) var totalDownloadStartTime: Date?
    private(set) var totalDownloadEndTime: Date?
    private(set) var isDownloadingAll: Bool = false
    
    // 성능 최적화를 위한 상수들
    static let maxAllowedConcurrentDownloads = 10
    static let defaultConcurrentDownloads = 3
    
    // 네트워크 모니터링
    private let networkMonitor = NWPathMonitor()
    private var networkQueue = DispatchQueue(label: "NetworkMonitor")
    private var currentNetworkPath: NWPath?
    
    // 다운로드 속도 추적
    private var downloadSpeedHistory: [Double] = []
    private var averageDownloadSpeed: Double = 0.0
    private let maxSpeedSamples = 10
    
    init(urls: [String]) {
        // 고성능 URLSession 구성
        let config = URLSessionConfiguration.default
        config.urlCache = nil // 캐싱 비활성화로 메모리 절약
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = min(10, max(4, ProcessInfo.processInfo.processorCount))
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 300.0
        
        // iOS 15+에서 사용 가능한 멀티패스 서비스
        if #available(iOS 15.0, *) {
            config.multipathServiceType = .handover
        }
        
        self.urlSession = URLSession(configuration: config)
        self.files = urls.map { USDZFileInfo(url: $0) }
        
        startNetworkMonitoring()
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
    
    private func downloadFile(at index: Int, retryCount: Int = 0) async {
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
            
            // 고성능 다운로드 요청 구성
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            
            let downloadStartTime = Date()
            let (data, response) = try await urlSession.data(for: request)
            let downloadDuration = Date().timeIntervalSince(downloadStartTime)
            
            files[index].downloadEndTime = Date()
            files[index].fileSize = Int64(data.count)
            files[index].isDownloaded = true
            files[index].isDownloading = false
            await MainActor.run { 
                self.currentActiveDownloads = max(0, self.currentActiveDownloads - 1) 
                // 다운로드 속도 업데이트
                self.updateDownloadSpeed(bytes: Int64(data.count), duration: downloadDuration)
            }
            
            // Create entity from downloaded data in background
            await createEntity(from: data, at: index)
            
        } catch {
            let errorMessage = handleDownloadError(error)
            files[index].error = errorMessage
            files[index].downloadEndTime = Date()
            files[index].isDownloading = false
            await MainActor.run { self.currentActiveDownloads = max(0, self.currentActiveDownloads - 1) }
            
            // 재시도 로직
            if shouldRetry(error: error) && retryCount < 2 {
                print("⚠️ Retrying download for file \(index) (attempt \(retryCount + 1))")
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000)) // 지수 백오프
                await downloadFile(at: index, retryCount: retryCount + 1)
            }
        }
    }
    
    /// 다운로드 에러 처리
    private func handleDownloadError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "다운로드 시간 초과"
            case .networkConnectionLost:
                return "네트워크 연결 끊김"
            case .notConnectedToInternet:
                return "인터넷 연결 없음"
            case .cannotFindHost:
                return "서버를 찾을 수 없음"
            default:
                return "네트워크 오류: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
    
    /// 재시도 여부 결정
    private func shouldRetry(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotFindHost:
                return true
            default:
                return false
            }
        }
        return false
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
    
    // MARK: - 고성능 다운로드 최적화 메소드들
    
    /// 네트워크 모니터링 시작
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.currentNetworkPath = path
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    /// 시스템 리소스를 고려한 최대 허용 동시 다운로드 수
    static func getMaxAllowedConcurrentDownloads() -> Int {
        return maxAllowedConcurrentDownloads
    }
    
    /// 현재 시스템 상태에 따른 권장 동시 다운로드 수
    func getRecommendedConcurrentDownloads() -> Int {
        return calculateOptimalConcurrentDownloads()
    }
    
    /// 유효한 동시 다운로드 수인지 확인
    func isValidConcurrentDownloads(_ count: Int) -> Bool {
        return count > 0 && count <= Self.maxAllowedConcurrentDownloads
    }
    
    /// 시스템 상태를 종합하여 최적의 동시 다운로드 수 계산
    func calculateOptimalConcurrentDownloads() -> Int {
        let processorCount = ProcessInfo.processInfo.processorCount
        let baseCount = max(2, min(processorCount, Self.defaultConcurrentDownloads))
        
        let networkMultiplier = getNetworkSpeedMultiplier()
        let performanceMultiplier = getDevicePerformanceMultiplier()
        let memoryMultiplier = getMemoryPressureMultiplier()
        
        let optimizedCount = Int(Double(baseCount) * networkMultiplier * performanceMultiplier * memoryMultiplier)
        
        return max(1, min(optimizedCount, Self.maxAllowedConcurrentDownloads))
    }
    
    /// 네트워크 속도에 따른 배수
    private func getNetworkSpeedMultiplier() -> Double {
        guard let path = currentNetworkPath else { return 1.0 }
        
        if path.isExpensive { return 0.7 } // 셀룰러 데이터일 때 줄임
        if !path.isConstrained { return 1.3 } // 제한 없는 네트워크일 때 늘림
        
        // 평균 다운로드 속도 기반 조정
        if averageDownloadSpeed > 10_000_000 { // 10MB/s 이상
            return 1.5
        } else if averageDownloadSpeed > 5_000_000 { // 5MB/s 이상
            return 1.2
        } else if averageDownloadSpeed < 1_000_000 { // 1MB/s 미만
            return 0.8
        }
        
        return 1.0
    }
    
    /// 기기 성능에 따른 배수
    private func getDevicePerformanceMultiplier() -> Double {
        let processorCount = ProcessInfo.processInfo.processorCount
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        
        // 8GB 이상의 RAM과 8코어 이상일 때
        if physicalMemory > 8_000_000_000 && processorCount >= 8 {
            return 1.5
        }
        // 4GB 이상의 RAM과 6코어 이상일 때
        else if physicalMemory > 4_000_000_000 && processorCount >= 6 {
            return 1.2
        }
        // 2GB 미만의 RAM일 때
        else if physicalMemory < 2_000_000_000 {
            return 0.7
        }
        
        return 1.0
    }
    
    /// 메모리 압박 상황에 따른 배수
    private func getMemoryPressureMultiplier() -> Double {
        // 더 안전한 메모리 체크 방법 사용
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryPressure = getSimpleMemoryPressure()
        
        switch memoryPressure {
        case .critical:
            return 0.5
        case .warning:
            return 0.7
        case .normal:
            return 1.0
        }
    }
    
    /// 간단한 메모리 압박 상태 체크
    private func getSimpleMemoryPressure() -> MemoryPressureLevel {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        
        // 물리적 메모리 기반으로 간단한 추정
        if physicalMemory < 2_000_000_000 { // 2GB 미만
            return .warning
        } else if physicalMemory < 1_000_000_000 { // 1GB 미만
            return .critical
        } else {
            return .normal
        }
    }
    
    /// 메모리 압박 레벨
    private enum MemoryPressureLevel {
        case normal
        case warning
        case critical
    }
    
    /// 다운로드 속도 업데이트
    private func updateDownloadSpeed(bytes: Int64, duration: TimeInterval) {
        guard duration > 0 else { return }
        
        let speed = Double(bytes) / duration
        downloadSpeedHistory.append(speed)
        
        if downloadSpeedHistory.count > maxSpeedSamples {
            downloadSpeedHistory.removeFirst()
        }
        
        averageDownloadSpeed = downloadSpeedHistory.reduce(0, +) / Double(downloadSpeedHistory.count)
    }
    
    /// 스마트 다운로드 - 시스템 상태에 따라 최적화된 다운로드
    func startSmartDownloading() async {
        let optimalConcurrency = calculateOptimalConcurrentDownloads()
        print("🧠 스마트 다운로드: 최적 동시성 = \(optimalConcurrency)")
        print("📊 시스템 정보:")
        print("   • CPU 코어: \(ProcessInfo.processInfo.processorCount)개")
        print("   • 물리적 메모리: \(String(format: "%.1f", Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000))GB")
        print("   • 네트워크 상태: \(getNetworkStatusDescription())")
        await startDownloadingAllWithLimit(maxConcurrentDownloads: optimalConcurrency)
    }
    
    /// 네트워크 상태 설명
    private func getNetworkStatusDescription() -> String {
        guard let path = currentNetworkPath else { return "알 수 없음" }
        
        var status = ""
        if path.usesInterfaceType(.wifi) {
            status += "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            status += "셀룰러"
        } else if path.usesInterfaceType(.wiredEthernet) {
            status += "유선"
        } else {
            status += "기타"
        }
        
        if path.isExpensive {
            status += " (데이터 제한)"
        }
        if path.isConstrained {
            status += " (대역폭 제한)"
        }
        
        return status
    }
    
    /// 현재 다운로드 통계 정보
    func getDownloadStatistics() -> DownloadStatistics {
        let successfulDownloads = files.filter { $0.isDownloaded }.count
        let failedDownloads = files.filter { $0.error != nil }.count
        let totalBytes = files.reduce(0) { $0 + $1.fileSize }
        let averageDuration = files.compactMap { $0.downloadDuration }.reduce(0, +) / Double(max(1, successfulDownloads))
        
        return DownloadStatistics(
            totalFiles: files.count,
            successfulDownloads: successfulDownloads,
            failedDownloads: failedDownloads,
            totalBytes: totalBytes,
            averageDownloadDuration: averageDuration,
            averageSpeed: averageDownloadSpeed
        )
    }
}

/// 다운로드 통계 정보
struct DownloadStatistics {
    let totalFiles: Int
    let successfulDownloads: Int
    let failedDownloads: Int
    let totalBytes: Int64
    let averageDownloadDuration: TimeInterval
    let averageSpeed: Double
    
    var successRate: Double {
        guard totalFiles > 0 else { return 0.0 }
        return Double(successfulDownloads) / Double(totalFiles) * 100.0
    }
    
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    var averageSpeedFormatted: String {
        let speedInMBps = averageSpeed / 1_000_000
        return String(format: "%.2f MB/s", speedInMBps)
    }
}

