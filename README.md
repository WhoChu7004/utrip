# 유튜버 추천 여행지

국내 여행 유튜브 영상에서 소개된 여행지를 모아 지도로 보여주는 페이지예요.
여러 채널이 같은 곳을 소개할수록 **추천수**가 올라가요.

**지도 보기:** https://whochu7004.github.io/utrip/

## 기능

- 대한민국 지도 위에 여행지 표시 (유형별 색상, 핀 묶음)
- 유형 필터, 여행지·지역·채널 검색
- 목록 정렬: 이름순, 추천순
- 여행지 상세: 위치, 요금, 추천 시기, 특징, 소개한 채널과 영상 링크, 네이버 지도·길찾기

## 데이터

- 원본: [`WWW/places.json`](WWW/places.json)
  - `videos`: 처리한 유튜브 영상 (중복 처리 방지)
  - `places`: 여행지 목록. 장소마다 소개한 영상과 채널을 가져요.
- 추천수 = 그 장소를 소개한 서로 다른 채널 수 (같은 채널의 영상이 여러 개면 1로 세요)
- 지도 페이지는 `places.json`으로 만든 [`WWW/data.js`](WWW/data.js)를 읽어요.
- 영상 정보는 유튜브 영상 페이지의 제목과 설명란에서 가져와요. 좌표와 요금은 공식 정보로 확인했지만 틀릴 수 있으니 방문 전에 다시 확인해 주세요.

## 업데이트 방법 (Windows PowerShell)

```powershell
cd WWW
# 유튜브 검색 / 영상 정보 읽기
powershell -ExecutionPolicy Bypass -File .\fetch-video.ps1 -Search "국내 여행지 추천" -ExcludeKnown
powershell -ExecutionPolicy Bypass -File .\fetch-video.ps1 -Url <videoId>
# 분석 결과(inbox\*.json)를 병합하고 data.js 다시 만들기
powershell -ExecutionPolicy Bypass -File .\merge-videos.ps1 -InputPath .\inbox\2026-10-25.json
# 바뀐 데이터(places.json, data.js, inbox)만 커밋해서 GitHub에 올리기
powershell -ExecutionPolicy Bypass -File .\publish-data.ps1
# 로컬에서 보기 (http://localhost:8080)
powershell -ExecutionPolicy Bypass -File .\serve.ps1
```

`main` 브랜치에 올리면 GitHub Actions가 지도 페이지를 GitHub Pages에 배포해요.
