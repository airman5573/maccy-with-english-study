# Maccy 영어공부 버전

macOS 클립보드 매니저인 [Maccy](https://github.com/p0deje/Maccy)를 영어공부용으로 조금 개조한 버전입니다.

문장을 복사하면 원문은 그대로 두고, 번역문을 Maccy 히스토리에 함께 추가합니다.

## 원본 프로젝트

- 원본: [p0deje/Maccy](https://github.com/p0deje/Maccy)
- 소개: macOS용 가볍고 빠른 오픈소스 클립보드 매니저
- 라이선스: MIT
- 지원 환경: macOS Sonoma 14 이상

## 추가된 기능

- 영어 문장을 복사하면 한국어 번역을 추가합니다.
- 한국어 문장을 복사하면 영어 번역을 추가합니다.
- 시스템 클립보드는 원문 그대로 유지합니다.
- 번역 결과는 Maccy 히스토리에 별도 항목으로 들어갑니다.
- 공부용 번역 기록을 따로 저장합니다.
- 짧은 텍스트, URL, 파일 경로, 이메일, 코드처럼 보이는 텍스트는 자동으로 건너뜁니다.

번역에는 DeepSeek API를 사용합니다. 번역 기능은 기본적으로 꺼져 있습니다.

## 설치

### 빌드된 앱을 받는 경우

1. 공유받은 `Maccy.app` 또는 압축 파일을 다운로드합니다.
2. `Maccy.app`을 `Applications` 폴더로 옮깁니다.
3. 처음 실행할 때 macOS가 차단하면 앱을 우클릭한 뒤 **Open**을 선택합니다.
4. 자동 붙여넣기 기능을 쓰려면 다음 권한을 허용합니다.
   - System Settings → Privacy & Security → Accessibility → Maccy 허용

> Homebrew로 `brew install maccy`를 실행하면 원본 Maccy가 설치됩니다. 이 버전의 번역 기능은 포함되지 않습니다.

### 직접 빌드하는 경우

1. Xcode에서 `Maccy.xcodeproj`를 엽니다.
2. Scheme을 `Maccy`로 선택합니다.
3. `Run`으로 실행하거나 `Product → Archive`로 앱을 만듭니다.
4. 빌드된 `Maccy.app`을 실행합니다.

## 번역 설정

1. Maccy를 실행합니다.
2. Preferences를 엽니다. 기본 단축키는 `⌘,` 입니다.
3. `Advanced` 탭에서 **DeepSeek translation**을 켭니다.
4. DeepSeek API key를 입력합니다.
5. 필요하면 모델 이름을 수정합니다. 기본값은 `deepseek-v4-flash`입니다.

API key는 macOS Keychain에 저장됩니다.

## 사용법

1. 번역하고 싶은 영어 또는 한국어 문장을 복사합니다.
2. Maccy가 번역 가능한 문장인지 판단합니다.
3. 번역이 성공하면 Maccy 히스토리에 번역문이 추가됩니다.
4. 기본 단축키 `⇧⌘C` 또는 메뉴바 아이콘으로 히스토리를 열어 확인합니다.
5. Preferences의 `Learning` 탭에서 저장된 번역 기록을 다시 볼 수 있습니다.

## 주의할 점

- 번역 기능을 켜면 번역 대상 텍스트가 DeepSeek API로 전송됩니다.
- 민감한 문장, 비밀번호, 개인정보는 복사하지 않는 것이 좋습니다.
- DeepSeek API 사용량에 따라 비용이 발생할 수 있습니다.
- 번역 품질은 API 응답에 따라 달라질 수 있습니다.

## 라이선스

이 프로젝트는 원본 Maccy와 동일하게 MIT 라이선스를 따릅니다.

자세한 내용은 [LICENSE](./LICENSE)를 확인하세요.
