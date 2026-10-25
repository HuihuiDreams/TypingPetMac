# Typing Pet for macOS

[한국어](README.md) · [English](README.en.md)

<p align="center">
  <a href="https://typing-pet.miel.ing/ko/"><strong>Typing Pet 홈페이지</strong></a>
</p>

설치 방법, 기능 안내, 업데이트 내역은 [홈페이지](https://typing-pet.miel.ing/ko/)에서 확인할 수 있습니다.

## 개발

Apple Silicon Mac, macOS 13 이상, Swift 6 및 Xcode Command Line Tools가 필요합니다. 개발 앱은 설치된 앱과 설정 및 데이터를 분리해 실행됩니다.

```sh
./scripts/run_dev.sh
```

테스트와 앱 빌드:

```sh
swift test
./scripts/build_app.sh
```

자세한 내용은 [개발 환경 안내](developer-notes/development.md)를 참고하세요.

## 프로젝트 참고

이 비공식 macOS 프로젝트는 [Windows용 Typing Pet](https://github.com/swoonqx/TypingPet)에서 영감을 받아 새로 구현했으며, 원본 소스 코드와 이미지 자산을 포함하지 않습니다.

- 소스 코드: [MIT](LICENSE)
- 기본 키보드 고양이 이미지: [CC0 1.0](ASSET_LICENSE.md)

기본 이미지는 이 저장소를 위한 AI 생성 플레이스홀더입니다. 사용자가 가져온 이미지의 권리는 원래 제작자에게 있습니다.
