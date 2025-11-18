//
//  NotificationNames.swift
//  USDZ_DownloadTest
//
//  Created by LeeMinJi on 11/18/25.
//

import Foundation

extension Notification.Name {
    /// USDZ 파일 하나의 다운로드 및 렌더링이 완료되었을 때 발송되는 notification
    static let usdzFileReady = Notification.Name("usdzFileReady")
    
    /// 모든 USDZ 파일의 다운로드가 완료되었을 때 발송되는 notification
    static let allUsdzFilesDownloadComplete = Notification.Name("allUsdzFilesDownloadComplete")
}

/// Notification의 userInfo에 전달할 key들
struct NotificationUserInfoKey {
    /// USDZFileInfo 객체를 전달할 때 사용하는 key
    static let fileInfo = "fileInfo"
    
    /// 파일 인덱스를 전달할 때 사용하는 key
    static let fileIndex = "fileIndex"
}