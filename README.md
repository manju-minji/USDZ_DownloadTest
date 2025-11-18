# USDZ Download Test

USDZ Download Test는 여러 개의 USDZ 파일을 네트워크에서 내려받아 RealityKit의 `Entity`로 로드(렌더 준비)하는 전체 흐름을 측정하고 시각화하기 위한 샘플 프로젝트입니다. 각 파일에 대해 다운로드 시작/종료 시간, 렌더 시작/종료 시간, 파일 크기 등을 기록하고, 전체 배치 다운로드의 총 소요 시간과 진행률을 제공합니다.

본 샘플은 visionOS를 주요 타겟으로 하며, RealityKit 기반의 엔티티 로드 흐름을 양 플랫폼에서 동일한 패턴으로 검증할 수 있습니다. 
본 프로젝트에는 Xcode Intelligence (GPT)가 사용되었습니다.

## 주요 기능
- 여러 USDZ 파일 동시 다운로드 및 제한된 동시성 다운로드 지원
- 파일별 다운로드/렌더링 시간 측정 및 서식화된 크기 표기
- 다운로드/렌더 완료 알림(Notification) 발송
- RealityKit `Entity` 로드 후 즉시 사용 가능한 엔티티 목록 제공
- 전체 배치 다운로드의 총 소요 시간 및 진행률 표시

## 기술 스택
- Swift 6 / Swift Concurrency (async/await, TaskGroup)
- SwiftUI
- RealityKit
- visionOS (RealityKit, SwiftUI)
- Foundation / URLSession

## 폴더 구조(핵심)
- `USDZDownloadManager.swift`: 다운로드/렌더링 로직과 상태 관리의 핵심 클래스

## 빌드 및 실행 방법
1. Xcode 16 이상(프로젝트에 맞는 최신 버전)을 사용하세요.
2. 프로젝트를 열고 타겟을 visionOS 시뮬레이터/기기로 설정합니다.
3. 실행(⌘R)하여 앱을 빌드하고 실행합니다.
4. `USDZDownloadManager` 초기화 시 전달하는 URL 배열을 원하는 USDZ URL로 교체하면 테스트 대상을 쉽게 바꿀 수 있습니다.

```swift
// 예시
let urls = [
    "https://example.com/model1.usdz",
    "https://example.com/model2.usdz"
]
let manager = USDZDownloadManager(urls: urls)
```


## 주요 코드 동작 원리

• URL 수집 및 상태 초기화
   • USDZDownloadManager는 초기화 시 전달된 URL 배열을 내부 상태에 등록하고, 각 항목에 대해 진행률/시간 측정용 메타데이터를 준비합니다.
   • 파일별로 다운로드 시작/종료, 렌더(엔티티 로드) 시작/종료 타임스탬프를 기록할 수 있는 구조를 갖춥니다.

• 제한된 동시성으로 다운로드 실행
   • Swift Concurrency의 withTaskGroup 혹은 withThrowingTaskGroup을 사용해 여러 USDZ 파일을 병렬로 내려받습니다.
   • 동시성 제한이 필요하면 세마포어나 커스텀 큐를 사용하거나, 그룹 내부에서 실행 개수를 제어합니다.

```swift
// 개념 예시
try await withThrowingTaskGroup(of: Void.self) { group in
    for url in urls {
        group.addTask { [weak self] in
            try await self?.downloadOne(url)
        }
    }
    try await group.waitForAll()
}
```

• 다운로드 시간 측정 및 크기 포맷팅
   • URLSession으로 데이터를 수신하면서 시작/종료 시간을 기록하고, 총 다운로드 시간을 계산합니다.
   • 수신한 데이터의 바이트 수를 사람이 읽기 쉬운 단위(예: KB/MB/GB)로 변환하여 표기합니다.

```swift
let start = Date()
let (data, response) = try await URLSession.shared.data(from: url)
let end = Date()
let elapsed = end.timeIntervalSince(start)
let sizeInBytes = data.count
```

• RealityKit 엔티티 로드(렌더 준비)
   • 다운로드 완료 후 임시 파일로 저장한 뒤, RealityKit의 Entity.load(contentsOf:) 또는 유사 API로 엔티티를 비동기 로드합니다.
   • 로드 시작/종료 시간을 별도로 기록하여 네트워크 시간과 렌더 준비 시간을 구분합니다.

```swift
let entity = try await Entity.load(contentsOf: localFileURL)
loadedEntities.append(entity)
```

 진행률/총 소요 시간 집계
   • 각 파일의 이벤트(다운로드 시작/종료, 렌더 시작/종료)를 합산해 배치 진행률과 총 소요 시간을 계산합니다.
   • SwiftUI 상태(@Published 등)로 바인딩하여 UI에 실시간 반영합니다.

• 알림(Notification) 및 상태 브로드캐스트
   • 파일 단위/배치 단위 완료 시 NotificationCenter로 알림을 발송하거나, 옵저버블 객체의 상태 변화를 통해 구독자에게 전달합니다.

• visionOS 고려 사항
   • RealityKit 엔티티 로드는 iOS/visionOS 모두 동일 패턴으로 동작합니다.
   • 시뮬레이터와 실제 기기 간 렌더 준비 시간 차이가 있을 수 있으므로, 큰 USDZ 파일은 동시성 수를 조절하거나 사전 프리페치 전략을 고려하세요.

