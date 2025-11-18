# USDZ Download Test

USDZ Download Test는 여러 개의 USDZ 파일을 네트워크에서 내려받아 RealityKit의 `Entity`로 로드(렌더 준비)하는 전체 흐름을 측정하고 시각화하기 위한 샘플 프로젝트입니다. 각 파일에 대해 다운로드 시작/종료 시간, 렌더 시작/종료 시간, 파일 크기 등을 기록하고, 전체 배치 다운로드의 총 소요 시간과 진행률을 제공합니다.

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
- Foundation / URLSession

## 폴더 구조(핵심)
- `USDZDownloadManager.swift`: 다운로드/렌더링 로직과 상태 관리의 핵심 클래스

## 빌드 및 실행 방법
1. Xcode 16 이상(프로젝트에 맞는 최신 버전)을 사용하세요.
2. 프로젝트를 열고 타겟을 iOS 시뮬레이터 또는 실제 기기로 설정합니다.
3. 실행(⌘R)하여 앱을 빌드하고 실행합니다.
4. `USDZDownloadManager` 초기화 시 전달하는 URL 배열을 원하는 USDZ URL로 교체하면 테스트 대상을 쉽게 바꿀 수 있습니다.

```swift
// 예시
let urls = [
    "https://example.com/model1.usdz",
    "https://example.com/model2.usdz"
]
let manager = USDZDownloadManager(urls: urls)

