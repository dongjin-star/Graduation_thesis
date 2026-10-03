# Graduation Thesis - TOPIS CCTV Recorder

서울시 TOPIS 교통 CCTV HLS(m3u8) 스트림을 녹화하는 스크립트. 졸업논문용 교통 영상 자료 수집 목적.

## 준비 (다른 PC에서 처음 설정할 때)

1. 이 저장소를 클론한다.
   ```
   git clone https://github.com/dongjin-star/Graduation_thesis.git
   cd Graduation_thesis
   ```

2. ffmpeg를 받는다. **반드시 아래 BtbN 빌드를 써야 한다.**
   `tools/` 폴더는 용량이 커서(약 500MB) `.gitignore`로 제외되어 git에 포함되지 않았다. 아래 주소에서 직접 받아서 압축을 푼다.

   ```
   https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip
   ```

   압축을 풀어서 다음 경로가 되도록 둔다:
   ```
   tools\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe
   ```

   **왜 이 빌드여야 하는가:** 일반적으로 winget/gyan.dev로 설치되는 ffmpeg는 TLS에 gnutls를 쓰는데, TOPIS 서버(`*.eseoul.go.kr`)가 핸드셰이크 중 중간 인증서(intermediate CA)를 보내지 않아서 gnutls가 인증서 체인을 완성하지 못하고 `Peer certificate failed verification` 에러로 실패한다. Windows의 schannel(브라우저/curl이 쓰는 것과 동일)은 누락된 중간 인증서를 자동으로 가져오는 기능(AIA fetching)이 있어서 문제가 없다. BtbN 빌드는 `--enable-schannel`로 빌드되어 있어 이 문제를 피할 수 있다.

   `tools/ffmpeg-...` 가 없으면 스크립트가 시스템 PATH의 ffmpeg로 대체 시도하지만, 그 경우 위 TLS 에러가 날 가능성이 높다.

## 사용법

### 1) 녹화

```powershell
.\Record-CCTV.ps1 -Url "<m3u8 주소>" -Duration 3600
```

- `-Duration`: 녹화 길이(초). 기본 60초(테스트용). 1시간 = 3600.
- 원본은 `recordings\{yyyyMMdd_HHmmss} ({길이}).mkv` 로 저장된다.
  - **mkv를 쓰는 이유:** mp4는 파일 끝에 인덱스(moov atom)를 한 번에 쓰기 때문에, 녹화 중 강제 종료(OOM 등)되면 전체 파일이 재생 불가능해진다. mkv는 점진적으로 기록되어 중간에 끊겨도 그 시점까지는 재생 가능하다.
- 녹화가 끝나면 **자동으로** 30fps 고정(CFR) `_fixed.mp4` 사본이 같은 폴더에 만들어진다 (`-SkipFix`로 끌 수 있음). 분석/재생은 이 `_fixed.mp4` 파일을 쓴다.

### 2) 보정 사본만 다시 만들고 싶을 때

```powershell
.\Fix-Recording.ps1 -InputFile ".\recordings\xxx.mkv"
```

- 기본값: 30fps CFR, libx264 crf 18. 원본은 그대로 두고 `_fixed.mp4`를 새로 만든다.

## 참고

- `recordings/`, `tools/` 는 git에 올라가지 않는다(`.gitignore`). 녹화 파일과 ffmpeg 바이너리는 각 PC에 로컬로만 존재한다.
- 장시간(1시간 이상) 녹화 전에는 PC의 여유 메모리를 확인하고, 가능하면 다른 무거운 프로그램을 닫아두는 것이 안전하다. (메모리 부족으로 ffmpeg 프로세스가 강제 종료된 적이 있었음.)
