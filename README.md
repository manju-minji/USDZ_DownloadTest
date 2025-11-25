# USDZ Download Test

USDZ Download Test는 여러 개의 USDZ 파일을 네트워크에서 내려받아 RealityKit의 `Entity`로 로드(렌더 준비)하는 전체 흐름을 측정하고 시각화하기 위한 샘플 프로젝트입니다. 각 파일에 대해 다운로드 시작/종료 시간, 렌더 시작/종료 시간, 파일 크기 등을 기록하고, 전체 배치 다운로드의 총 소요 시간과 진행률을 제공합니다.

본 샘플은 visionOS를 주요 타겟으로 하며, RealityKit 기반의 엔티티 로드 흐름을 양 플랫폼에서 동일한 패턴으로 검증할 수 있습니다. 
본 프로젝트에는 Xcode Intelligence (GPT)가 사용되었습니다.

## 주요 기능
- **지능형 동시성 제어**: 시스템 리소스를 실시간 분석하여 최적의 동시 다운로드 수 자동 결정
- **다중 다운로드 전략**: 순차, 제한적 동시, 무제한 동시, 스마트 다운로드 등 다양한 옵션
- **실시간 성능 모니터링**: 네트워크 속도, CPU 사용률, 메모리 압박 상태 추적
- **파일별 세부 측정**: 다운로드/렌더링 시간, 파일 크기, 에러 처리 및 재시도 로직
- **고성능 URLSession**: HTTP/2, 멀티패스 네트워킹, 압축 최적화
- **다운로드/렌더 완료 알림(Notification)**: 개별 파일 및 전체 배치 완료 이벤트
- **RealityKit `Entity` 즉시 사용**: 로드 완료된 엔티티 목록 실시간 제공

## 🧠 스마트 다운로드 시스템

### 권장 동시성 계산 공식
```
최종 동시성 = 기본값 × 네트워크배수 × 성능배수 × 메모리배수
```

#### 1. **기본값 (Base Count)**
- CPU 코어 수와 기본 제한값(3) 중 작은 값 선택
- 최소 2개 보장

```swift
let baseCount = max(2, min(processorCount, 3))
```

#### 2. **네트워크 배수 (0.7 ~ 1.5배)**
| 네트워크 상태 | 배수 | 비고 |
|--------------|------|------|
| 셀룰러 (데이터 제한) | 0.7× | 30% 감소 |
| WiFi (무제한) | 1.3× | 30% 증가 |
| 고속 (10MB/s+) | 1.5× | 50% 증가 |
| 중속 (5MB/s+) | 1.2× | 20% 증가 |
| 저속 (1MB/s-) | 0.8× | 20% 감소 |

#### 3. **기기 성능 배수 (0.7 ~ 1.5배)**
| 기기 사양 | 배수 | 조건 |
|----------|------|------|
| 고성능 | 1.5× | 8GB+ RAM, 8+ 코어 |
| 중급 | 1.2× | 4GB+ RAM, 6+ 코어 |
| 저사양 | 0.7× | 2GB- RAM |
| 표준 | 1.0× | 기타 |

#### 4. **메모리 압박 배수 (0.5 ~ 1.0배)**
| 메모리 상태 | 배수 | 설명 |
|-------------|------|------|
| 정상 | 1.0× | 충분한 메모리 |
| 경고 | 0.7× | 메모리 부족 징후 |
| 위험 | 0.5× | 심각한 메모리 압박 |

### 실제 계산 예시

#### 고성능 기기 (iPhone 15 Pro)
- 기본값: `min(8, 3) = 3`
- 네트워크: WiFi 고속 → `1.3`
- 성능: 8GB + 8코어 → `1.5`
- 메모리: 정상 → `1.0`
- **결과**: `3 × 1.3 × 1.5 × 1.0 = 5.85` → **6개**

#### 중급 기기 (iPhone 13)
- 기본값: `min(6, 3) = 3`
- 네트워크: WiFi 보통 → `1.0`
- 성능: 4GB + 6코어 → `1.2`
- 메모리: 정상 → `1.0`
- **결과**: `3 × 1.0 × 1.2 × 1.0 = 3.6` → **4개**

#### 저사양 기기 (구형 iPhone)
- 기본값: `min(4, 3) = 3`
- 네트워크: 셀룰러 → `0.7`
- 성능: 2GB 미만 → `0.7`
- 메모리: 경고 → `0.7`
- **결과**: `3 × 0.7 × 0.7 × 0.7 = 1.03` → **1개**

### 안전 장치
- **최소 보장**: 1개 이상
- **최대 제한**: 10개 이하
- **실시간 조정**: 네트워크/메모리 상태 변화 시 동적 재계산

## 다운로드 전략 옵션

| 전략 | 용도 | 특징 |
|------|------|------|
| 🧠 스마트 다운로드 | **권장** | 시스템 자동 최적화 |
| 🚀 고성능 다운로드 | 고사양 기기 | 최대 성능 활용 |
| ⚡ 제한적 동시 | 배터리 절약 | 사용자 지정 동시성 |
| 📱 순차 다운로드 | 극저사양 | 안정성 우선 |

## 기술 스택
- Swift 6 / Swift Concurrency (async/await, TaskGroup)
- SwiftUI with @Observable
- RealityKit
- Network Framework (실시간 네트워크 모니터링)
- Foundation / URLSession (HTTP/2, 멀티패스)
- visionOS (RealityKit, SwiftUI)

## 사용법

### 기본 사용법
```swift
// AppModel에서 다운로드 시작
let appModel = AppModel()

// 1. 스마트 다운로드 (권장)
appModel.startSmartDownloading()

// 2. 고성능 다운로드
appModel.startHighPerformanceDownloading()

// 3. 커스텀 동시성
appModel.downloadAllWithLimit(maxConcurrent: 5)
```

### 상황별 권장 전략
- **일반 사용**: `startSmartDownloading()` - 시스템이 자동으로 최적화
- **고사양 기기 + WiFi**: `startHighPerformanceDownloading()` - 최대 성능
- **배터리 절약**: `startDownloadingSequentiallyViaLimit()` - 순차 다운로드
- **네트워크 제한**: `downloadAllWithLimit(maxConcurrent: 2)` - 낮은 동시성

### 실시간 모니터링
```swift
let manager = appModel.usdzDownloadManager

// 진행률 확인
print("진행률: \(Int(manager.downloadProgress * 100))%")

// 성능 정보
print("권장 동시성: \(manager.getRecommendedConcurrentDownloads())개")
print("활성 다운로드: \(manager.currentActiveDownloads)개")

// 통계 정보
let stats = manager.getDownloadStatistics()
print("성공률: \(String(format: "%.1f", stats.successRate))%")
print("평균 속도: \(stats.averageSpeedFormatted)")
```

## 폴더 구조(핵심)
- `USDZDownloadManager.swift`: 다운로드/렌더링 로직과 상태 관리의 핵심 클래스
- `AppModel.swift`: 앱 전역 상태 관리 및 다운로드 전략 제공
- `ContentView.swift`: 실시간 진행률 및 시스템 정보 UI
- `NotificationNames.swift`: 다운로드 완료 알림 정의

## 빌드 및 실행 방법
1. Xcode 16 이상(프로젝트에 맞는 최신 버전)을 사용하세요.
2. 프로젝트를 열고 타겟을 visionOS 시뮬레이터/기기로 설정합니다.
3. 실행(⌘R)하여 앱을 빌드하고 실행합니다.
4. UI에서 원하는 다운로드 전략을 선택합니다:
   - **"🧠 스마트 다운로드"** 버튼 클릭 (권장)
   - **"🚀 고성능 다운로드"** 버튼 클릭
   - 또는 슬라이더로 동시성 조정 후 **"제한적 동시 다운로드"** 클릭

5. `AppModel`의 `defaultUSDZURLs`를 변경하여 원하는 USDZ URL로 테스트할 수 있습니다.

```swift
// 예시
static let defaultUSDZURLs: [String] = [
    "https://developer.apple.com/augmented-reality/quick-look/models/drummertoy/toy_drummer.usdz",
    "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz"
]
```


## 주요 코드 동작 원리

### 🧠 지능형 동시성 결정 알고리즘
```swift
func calculateOptimalConcurrentDownloads() -> Int {
    let processorCount = ProcessInfo.processInfo.processorCount
    let baseCount = max(2, min(processorCount, Self.defaultConcurrentDownloads))
    
    let networkMultiplier = getNetworkSpeedMultiplier()      // 0.7 ~ 1.5
    let performanceMultiplier = getDevicePerformanceMultiplier()  // 0.7 ~ 1.5
    let memoryMultiplier = getMemoryPressureMultiplier()     // 0.5 ~ 1.0
    
    let optimizedCount = Int(Double(baseCount) * networkMultiplier * performanceMultiplier * memoryMultiplier)
    
    return max(1, min(optimizedCount, Self.maxAllowedConcurrentDownloads))
}
```

### 🌐 실시간 네트워크 모니터링
```swift
private func startNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
        Task { @MainActor [weak self] in
            self?.currentNetworkPath = path
            // 네트워크 상태 변화 시 동시성 재계산
        }
    }
    networkMonitor.start(queue: networkQueue)
}
```

### ⚡ 고성능 URLSession 최적화
```swift
let config = URLSessionConfiguration.default
config.httpMaximumConnectionsPerHost = min(10, max(4, ProcessInfo.processInfo.processorCount))
config.timeoutIntervalForRequest = 30.0
config.timeoutIntervalForResource = 300.0

// iOS 15+ 멀티패스 네트워킹
if #available(iOS 15.0, *) {
    config.multipathServiceType = .handover
}
```

### URL 수집 및 상태 초기화
* USDZDownloadManager는 초기화 시 전달된 URL 배열을 내부 상태에 등록하고, 각 항목에 대해 진행률/시간 측정용 메타데이터를 준비합니다.
* 파일별로 다운로드 시작/종료, 렌더(엔티티 로드) 시작/종료 타임스탬프를 기록할 수 있는 구조를 갖춥니다.

### 🔄 TaskGroup을 활용한 동시성 제어
* Swift Concurrency의 `withTaskGroup`을 사용해 여러 USDZ 파일을 병렬로 내려받습니다.
* 동시성 제한이 필요하면 TaskGroup 내부에서 실행 개수를 동적으로 제어합니다.

```swift
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
```

### ⏱️ 정밀한 성능 측정
* 다운로드와 렌더링을 각각 별도로 측정하여 정확한 성능 분석을 제공합니다.
* 실시간 다운로드 속도 추적으로 네트워크 성능을 동적으로 반영합니다.

```swift
let downloadStartTime = Date()
let (data, response) = try await urlSession.data(for: request)
let downloadDuration = Date().timeIntervalSince(downloadStartTime)

files[index].downloadEndTime = Date()
files[index].fileSize = Int64(data.count)

// 다운로드 속도 업데이트
self.updateDownloadSpeed(bytes: Int64(data.count), duration: downloadDuration)
```

### 🔄 지능형 재시도 메커니즘
```swift
if shouldRetry(error: error) && retryCount < 2 {
    print("⚠️ Retrying download for file \(index) (attempt \(retryCount + 1))")
    // 지수 백오프로 재시도 간격 증가
    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
    await downloadFile(at: index, retryCount: retryCount + 1)
}
```

### 🎭 RealityKit 엔티티 로드 최적화
* 다운로드 완료 후 임시 파일로 저장한 뒤, RealityKit의 `Entity(contentsOf:)`로 비동기 엔티티 로드
* 로드 시작/종료 시간을 별도로 기록하여 네트워크 시간과 렌더 준비 시간을 구분합니다.
* 임시 파일은 엔티티 로드 완료 후 즉시 정리하여 메모리 효율성을 확보합니다.

```swift
// 임시 파일 생성 및 엔티티 로드
let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_\(index).usdz")
try data.write(to: tempURL)

let entity = try await Entity(contentsOf: tempURL)
files[index].entity = entity
files[index].isRendered = true

// 즉시 정리
try? FileManager.default.removeItem(at: tempURL)
```

### 📊 실시간 통계 및 진행률 추적
* 각 파일의 이벤트를 실시간으로 집계하여 배치 진행률과 총 소요 시간을 계산합니다.
* SwiftUI의 `@Observable`과 바인딩하여 UI에 실시간 반영합니다.

### 알림(Notification) 및 상태 브로드캐스트
* 파일 단위/배치 단위 완료 시 NotificationCenter로 알림을 발송하거나, 옵저버블 객체의 상태 변화를 통해 구독자에게 전달합니다.

### visionOS 및 성능 고려 사항
* RealityKit 엔티티 로드는 iOS/visionOS 모두 동일 패턴으로 동작합니다.
* 시뮬레이터와 실제 기기 간 렌더 준비 시간 차이가 있을 수 있으므로, 큰 USDZ 파일은 스마트 동시성 제어를 통해 최적화됩니다.
* 실시간 시스템 모니터링으로 메모리 압박이나 네트워크 상태 변화에 동적으로 대응합니다.

## 🎯 성능 벤치마크

### 예상 성능 (WiFi 환경)
| 기기 사양 | 권장 동시성 | 예상 소요 시간 | 특징 |
|----------|-------------|---------------|------|
| 고성능 (iPhone 15 Pro) | 6-8개 | 10-15초 | 최적 성능 |
| 중급 (iPhone 13) | 4-5개 | 15-25초 | 균형 잡힌 성능 |
| 저사양 (구형 iPhone) | 1-2개 | 30-45초 | 안정성 우선 |

### 네트워크별 최적화
- **WiFi 6**: 최대 동시성 활용
- **WiFi 5**: 중간 수준 동시성
- **셀룰러**: 데이터 절약 모드 자동 적용


https://github.com/user-attachments/assets/04a59755-f353-4481-a162-7563c77333c6


