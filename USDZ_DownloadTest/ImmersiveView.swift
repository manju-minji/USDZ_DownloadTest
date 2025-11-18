//
//  ImmersiveView.swift
//  USDZ_DownloadTest
//
//  Created by LeeMinJi on 11/17/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var contentEntity: Entity?
    @State private var addedEntities: Set<UUID> = [] // 이미 추가된 Entity들의 ID를 추적
    
    // MARK: - Constants
    private let targetModelSize: Float = 0.3 // 모든 모델의 목표 크기 (가장 큰 차원 기준)
    private let modelSpacing: Float = 0.4 // 모델 간 간격 (좀 더 넓게)

    var body: some View {
        RealityView { content in
            // Create a parent entity to hold all USDZ models
            let parentEntity = Entity()
            parentEntity.name = "USDZModelsContainer"
            content.add(parentEntity)
            contentEntity = parentEntity
            
            print("🏗️ RealityView setup complete, parent entity added")
            
        } update: { content in
            // Update closure for debugging
            guard let parentEntity = contentEntity else { return }
            print("🔄 RealityView update - Children count: \(parentEntity.children.count)")
        }
        .onReceive(NotificationCenter.default.publisher(for: .usdzFileReady)) { notification in
            handleFileReadyNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .allUsdzFilesDownloadComplete)) { _ in
            handleAllDownloadCompleteNotification()
        }
        .onAppear {
            print("🚀 ImmersiveView appeared")
        }
    }
    
    
    // MARK: - Notification Handlers
    
    /// 개별 파일 다운로드 완료 notification 처리
    private func handleFileReadyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let fileInfo = userInfo[NotificationUserInfoKey.fileInfo] as? USDZFileInfo,
              let index = userInfo[NotificationUserInfoKey.fileIndex] as? Int else {
            print("❌ Invalid notification userInfo")
            return
        }
        
        print("📥 Received notification for file \(index): \(fileInfo.fileName)")
        
        // 에러가 있거나 entity가 없는 경우 처리하지 않음
        guard fileInfo.error == nil, let entity = fileInfo.entity else {
            print("⚠️ Skipping file \(index) due to error or missing entity")
            return
        }
        
        // 이미 추가된 entity인지 확인
        if addedEntities.contains(fileInfo.id) {
            print("⚠️ Entity already added for file \(index)")
            return
        }
        
        // 새로운 entity 추가
        addEntityToScene(entity: entity, fileInfo: fileInfo, index: index)
    }
    
    /// 모든 다운로드 완료 notification 처리
    private func handleAllDownloadCompleteNotification() {
        print("📥 Received notification: All downloads complete")
        print("📊 Total entities in scene: \(contentEntity?.children.count ?? 0)")
    }
    
    /// Scene에 entity 추가
    private func addEntityToScene(entity: Entity, fileInfo: USDZFileInfo, index: Int) {
        guard let parentEntity = contentEntity else { 
            print("❌ parentEntity is nil")
            return 
        }
        
        print("✅ Adding entity for file: \(fileInfo.fileName)")
        
        // 모델을 목표 크기로 정규화
        normalizeEntitySize(entity)
        
        // parentEntity에 추가
        parentEntity.addChild(entity)
        
        // 추가된 entity ID 기록
        addedEntities.insert(fileInfo.id)
        
        print("🔄 Repositioning \(parentEntity.children.count) models")
        
        // 전체 모델들의 위치를 재계산
        repositionAllModels()
    }
    
    // MARK: - Model Sizing and Positioning
    
    /// Entity의 크기를 목표 크기로 정규화
    private func normalizeEntitySize(_ entity: Entity) {
        print("🔍 Normalizing entity: \(entity)")
        
        // 먼저 기본 스케일로 설정
        entity.setScale(SIMD3<Float>(repeating: 1.0), relativeTo: nil)
        
        // 바운딩 박스 계산 시도
        let boundingBox = entity.visualBounds(relativeTo: nil)
        let currentSize = boundingBox.extents
        
        print("📦 Bounding box - Size: \(currentSize), Center: \(boundingBox.center)")
        
        // 가장 큰 차원 찾기
        let maxDimension = max(currentSize.x, currentSize.y, currentSize.z)
        
        print("📏 Max dimension: \(maxDimension)")
        
        // 최대 차원이 0이거나 너무 작으면 기본 스케일 사용
        guard maxDimension > 0.001 else {
            print("⚠️ Entity has zero or very small dimensions, using default scale")
            let defaultScale = SIMD3<Float>(repeating: 0.1) // 기본 스케일
            entity.setScale(defaultScale, relativeTo: nil)
            return
        }
        
        // 목표 크기에 맞는 스케일 팩터 계산
        let scaleFactor = targetModelSize / maxDimension
     
        // 스케일 팩터가 너무 극단적이지 않도록 제한
        let clampedScaleFactor = max(0.001, min(10.0, scaleFactor))
        let clampedScale = SIMD3<Float>(repeating: clampedScaleFactor)
        
        // 정규화된 크기로 설정
        entity.setScale(clampedScale, relativeTo: nil)
        
        print("📏 Applied scale: \(clampedScale) (original factor: \(scaleFactor))")
    }
    
    private func repositionAllModels() {
        guard let parentEntity = contentEntity else { return }
        
        let totalCount = parentEntity.children.count
        
        // 모델이 없는 경우 early return
        guard totalCount > 0 else { return }
        
        let startX: Float = -Float(totalCount - 1) * modelSpacing / 2.0 // 중앙에서 시작하도록 조정
        
        print("📍 Repositioning \(totalCount) models, startX: \(startX)")
        
        for (index, entity) in parentEntity.children.enumerated() {
            // 위치 설정 (왼쪽부터 오른쪽으로)
            let position = SIMD3<Float>(startX + Float(index) * modelSpacing, 0.4, -1) // Z를 -2로 변경하여 더 가깝게
            
            // 모든 entity의 크기를 균일하게 재설정 (안전을 위해)
            normalizeEntitySize(entity)
            entity.position = position
            
            // 디버깅을 위해 transform 정보 출력
            print("   Model \(index): position = \(position), scale = \(entity.scale), transform = \(entity.transform)")
            
            // Entity가 실제로 렌더링 가능한 컴포넌트를 가지고 있는지 확인
            if entity.components.has(ModelComponent.self) {
                print("   ✅ Model \(index) has ModelComponent")
            } else {
                print("   ❌ Model \(index) missing ModelComponent")
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
