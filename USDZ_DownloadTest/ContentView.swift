//
//  ContentView.swift
//  USDZ_DownloadTest
//
//  Created by LeeMinJi on 11/17/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
import Combine

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var maxConcurrentDownloads: Double = 3

    var body: some View {
        VStack(spacing: 20) {
            Text("USDZ 파일 다운로드 상태")
                .font(.largeTitle)
                .padding()
            
            // 전체 다운로드 상태 표시
            VStack(spacing: 12) {
                HStack {
                    Text("전체 진행률:")
                        .font(.headline)
                    Spacer()
                    Text("\(appModel.usdzDownloadManager.completedDownloadsCount) / \(appModel.usdzDownloadManager.totalFilesCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: appModel.usdzDownloadManager.downloadProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    Text("현재 활성 다운로드: \(appModel.usdzDownloadManager.currentActiveDownloads)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                HStack {
                    if appModel.usdzDownloadManager.isDownloadingAll {
                        Text("다운로드 중...")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        ElapsedTimeView(startTime: appModel.usdzDownloadManager.totalDownloadStartTime)
                    } else if let _ = appModel.usdzDownloadManager.totalDownloadDuration {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("총 소요 시간: \(appModel.usdzDownloadManager.totalDownloadDurationFormatted)")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            HStack {
                                let totalSize = appModel.usdzDownloadManager.files.reduce(0) { $0 + $1.fileSize }
                                let downloadedCount = appModel.usdzDownloadManager.files.filter { $0.isDownloaded }.count
                                let errorCount = appModel.usdzDownloadManager.files.filter { $0.error != nil }.count
                                
                                Text("다운로드 완료: \(downloadedCount)개")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if errorCount > 0 {
                                    Text("실패: \(errorCount)개")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                                
                                if totalSize > 0 {
                                    Text("총 크기: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            List(appModel.usdzDownloadManager.files) { file in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(file.fileName)
                            .font(.headline)
                        Spacer()
                        StatusIndicator(file: file)
                    }
                    
                    if file.isDownloaded {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("파일 크기: \(file.fileSizeFormatted)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let downloadDuration = file.downloadDuration {
                                    Text("다운로드 시간: \(String(format: "%.2f", downloadDuration))초")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let renderDuration = file.renderDuration {
                                    Text("렌더링 시간: \(String(format: "%.2f", renderDuration))초")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    
                    if let error = file.error {
                        Text("오류: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 4)
            }
            
            VStack(spacing: 16) {
                HStack {
                    Text("제한적 동시 다운로드의 수: \(Int(maxConcurrentDownloads))")
                        .font(.subheadline)
                    Spacer()
                }
                Slider(value: $maxConcurrentDownloads, in: 1...10, step: 1) {
                    Text("동시 다운로드 수")
                } minimumValueLabel: {
                    Text("1")
                } maximumValueLabel: {
                    Text("10")
                }
                .disabled(appModel.usdzDownloadManager.isDownloadingAll)
                
                HStack(spacing: 12) {
                    Button("순차 다운로드") {
                        Task {
                            await appModel.usdzDownloadManager.startDownloadingSequentially()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.usdzDownloadManager.isDownloadingAll)
                    
                    Button("동시 다운로드") {
                        appModel.downloadAllConcurrently()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.usdzDownloadManager.isDownloadingAll)
                    
                    Button("제한적 동시 다운로드") {
                        appModel.downloadAllWithLimit(maxConcurrent: Int(maxConcurrentDownloads))
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.usdzDownloadManager.isDownloadingAll)
                }
                
                ToggleImmersiveSpaceButton()
            }
        }
        .padding()
    }
}

// 실시간 경과 시간을 표시하는 뷰
struct ElapsedTimeView: View {
    let startTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    
    var body: some View {
        Text("경과 시간: \(String(format: "%.1f", elapsedTime))초")
            .font(.caption)
            .foregroundColor(.secondary)
            .onAppear {
                updateElapsedTime()
            }
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                updateElapsedTime()
            }
    }
    
    private func updateElapsedTime() {
        guard let startTime = startTime else {
            elapsedTime = 0
            return
        }
        elapsedTime = Date().timeIntervalSince(startTime)
    }
}

struct StatusIndicator: View {
    let file: USDZFileInfo
    
    var body: some View {
        HStack(spacing: 4) {
            if file.error != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            } else if file.isRendered {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if file.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
            } else if file.isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("다운로드 중...")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if file.downloadStartTime != nil {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
