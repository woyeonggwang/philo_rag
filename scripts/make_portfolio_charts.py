"""포트폴리오 PPT 용 그림 4장 -> output/Portfolio/useimage/ (흐름도, 검색 A/B, 개념어 사전, 평가).
숫자는 CLAUDE.md 와 output/Portfolio/eval/report-2026-10-14.md 그대로다. 글꼴은 Windows 의 맑은 고딕.
실행: python scripts/make_portfolio_charts.py  (base anaconda — matplotlib 필요. API 호출 없음)
"""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
from matplotlib.patches import FancyBboxPatch

OUT = str(Path(__file__).resolve().parent.parent / "output" / "Portfolio" / "useimage") + "/"
for f in ["C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/malgunbd.ttf"]:
    fm.fontManager.addfont(f)
plt.rcParams["font.family"] = "Malgun Gothic"
plt.rcParams["axes.unicode_minus"] = False

BG, INK, GRAY, LIGHT, LINE, SEAL = "#FFFFFF", "#252525", "#8A8A8A", "#D9D9D6", "#BDBDBA", "#A8442E"


def save(fig, name):
    fig.savefig(OUT + name, dpi=100, facecolor=BG)
    plt.close(fig)


# ---------------------------------------------------------------- 1. 요청 처리 흐름
fig = plt.figure(figsize=(19.2, 10.8))
ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, 192); ax.set_ylim(0, 108); ax.axis("off")

def box(x, y, w, h, title, sub="", dark=False, seal=False, fs=17):
    fc = INK if dark else ("#FFF4F1" if seal else "#F6F6F4")
    ec = SEAL if seal else INK
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.6,rounding_size=2.2",
                                fc=fc, ec=ec, lw=2))
    tc = "#FFFFFF" if dark else INK
    if sub:
        ax.text(x + w / 2, y + h * 0.64, title, ha="center", va="center", fontsize=fs, color=tc, weight="bold")
        ax.text(x + w / 2, y + h * 0.30, sub, ha="center", va="center", fontsize=fs - 4, color="#DDDDDD" if dark else "#555555", linespacing=1.4)
    else:
        ax.text(x + w / 2, y + h / 2, title, ha="center", va="center", fontsize=fs, color=tc, weight="bold")

def arrow(x1, y1, x2, y2, label="", color=INK, rad=0.0, ls="-"):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=2, mutation_scale=22,
                                connectionstyle=f"arc3,rad={rad}", linestyle=ls))
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 1.8, label, ha="center", va="bottom", fontsize=13, color=color)

ax.text(6, 101, "요청 처리 흐름", fontsize=30, weight="bold", color=INK, va="center")
ax.text(6, 95, "앱은 {persona, question} 만 보낸다 — 키 · 임베딩 모델 · 벡터 검색은 전부 서버에", fontsize=15, color=GRAY, va="center")

box(4, 46, 22, 14, "앱 요청", "persona, question")
box(34, 42, 26, 22, "질문 분류", "① 위기 정규식 (호출 없음)\n② LLM 1회 → 6갈래", dark=True)
arrow(26.6, 53, 33.4, 53)

rows = [  # (y, 분류, 처리, seal)
    (78, "위기", "사람이 쓴 고정 안내(109) + 짧은 위로\n검색하지 않는다", True),
    (59, "미혹 (사이비)", "문구로 고른 경계 구절 고정\n예수는 \"거짓 선지자\" 필수", False),
    (40, "행적 · 가르침", "개념어 보강 → BGE-M3 임베딩\n→ 철학자별 FAISS 검색", False),
    (21, "토론 · 잡담", "코드가 첫 문장을 붙임\n\"직접 다룬 문제가 아니다\" · 온도 0.7", False),
]
for y, t, s, seal in rows:
    box(72, y, 40, 13, t, s, seal=seal, fs=16)
    arrow(60.6, 53, 71.4, y + 6.5, color=SEAL if seal else INK)

box(124, 42, 22, 22, "LLM 답변 생성", "gpt-5.6-luna\n추론 끔 · 온도 0", dark=True)
for y, *_ in rows:
    arrow(112.6, y + 6.5, 123.4, 53, color=LINE)

box(156, 46, 30, 14, "guard 규칙 검사", "영어 · 3인칭 · 말투 · 출처 표기 · 길이")
arrow(146.6, 53, 155.4, 53)
arrow(171, 60.8, 136, 64.8, color=SEAL, rad=0.55)
ax.text(153.5, 76, "위반 → 무엇을 어겼는지 알려 주고 재생성", ha="center", va="bottom", fontsize=13, color=SEAL)

box(156, 18, 30, 14, "응답", "answer · sources · glossary · usage")
arrow(171, 45.4, 171, 32.6)
ax.text(173, 39, "통과", ha="left", va="center", fontsize=13, color=INK)
ax.text(171, 12, "근거 구절은 위치만 (\"마태복음 3:1~3:15\")", ha="center", fontsize=12, color=GRAY)
save(fig, "s04-flow.png")


# ---------------------------------------------------------------- 2. 검색 A/B
fig, ax = plt.subplots(figsize=(12.8, 7.2))
fig.subplots_adjust(left=0.2, right=0.93, top=0.8, bottom=0.14)
labels = ["512 토큰 · 한국어 질문", "256 토큰 · 한국어 질문", "256 토큰 · 영어 번역", "512 토큰 · 영어 번역"]
vals = [0.619, 0.512, 0.462, 0.262]
colors = [INK, LIGHT, LIGHT, LIGHT]
bars = ax.barh(labels[::-1], vals[::-1], color=colors[::-1], height=0.6)
for b, v in zip(bars, vals[::-1]):
    ax.text(v + 0.01, b.get_y() + b.get_height() / 2, f"{v:.3f}", va="center", fontsize=17,
            color=INK, weight="bold" if v == 0.619 else "normal")
ax.set_xlim(0, 0.75); ax.tick_params(axis="y", labelsize=16, length=0); ax.tick_params(axis="x", labelsize=12, colors=GRAY)
for s in ["top", "right", "left"]: ax.spines[s].set_visible(False)
ax.spines["bottom"].set_color(LINE)
fig.text(0.05, 0.92, "청크 크기 · 질의 언어별 검색 정확도 (MRR)", fontsize=22, weight="bold", color=INK)
fig.text(0.05, 0.86, "채택: 512 토큰 + 한국어 질문 그대로 — 영어로 번역하면 오히려 가장 나빴다", fontsize=14, color=GRAY)
fig.text(0.05, 0.04, "질문 7개, 정답 구절을 사람이 지정 (방향 확인용 측정)", fontsize=12, color=GRAY)
save(fig, "s05-chart-retrieval.png")


# ---------------------------------------------------------------- 3. 개념어 사전 순위
fig, ax = plt.subplots(figsize=(12.8, 7.2))
fig.subplots_adjust(left=0.24, right=0.9, top=0.74, bottom=0.12)
items = [("아모르파티 (니체)", 26), ("운명애 (니체)", 31), ("위버멘쉬 (니체)", 31), ("열반 (부처)", 7),
         ("팔정도 (부처)", 25), ("팔복 (예수)", 31), ("오병이어 (예수)", 14), ("십자가 → 구레네 시몬 대목 (예수)", 13)]
items = items[::-1]
for i, (name, before) in enumerate(items):
    ax.plot([1, before], [i, i], color=LINE, lw=3, zorder=1)
    ax.scatter([before], [i], s=140, color="#FFFFFF", edgecolor=GRAY, lw=2, zorder=2)
    ax.scatter([1], [i], s=160, color=SEAL, zorder=3)
    ax.text(before + 0.8, i, "30위 밖" if before > 30 else f"{before}위", va="center", fontsize=14, color=GRAY)
ax.text(1, len(items) - 0.35, "1위", ha="center", fontsize=14, color=SEAL, weight="bold")
ax.set_yticks(range(len(items))); ax.set_yticklabels([n for n, _ in items], fontsize=15)
ax.set_xlim(-1, 35); ax.set_xticks([1, 10, 20, 30]); ax.set_xticklabels(["1위", "10위", "20위", "30위"], fontsize=12, color=GRAY)
ax.tick_params(axis="y", length=0)
for s in ["top", "right", "left"]: ax.spines[s].set_visible(False)
ax.spines["bottom"].set_color(LINE)
fig.text(0.05, 0.92, "개념어 사전 — 정답 구절의 검색 순위", fontsize=22, weight="bold", color=INK)
fig.text(0.05, 0.86, "「OO란 무엇입니까?」 회색 = 그대로 검색, 붉은 점 = 검색어에만 원어를 덧붙인 뒤 (예: 아모르파티 → amor fati)", fontsize=14, color=GRAY)
save(fig, "s08-chart-concepts.png")


# ---------------------------------------------------------------- 4. 평가 전후
fig, ax = plt.subplots(figsize=(12.8, 7.2))
fig.subplots_adjust(left=0.2, right=0.95, top=0.74, bottom=0.2)
rows = [("수정 후 (31문항)", 29, 2, 0), ("첫 측정 (30문항)", 23, 4, 3)]
for i, (name, p, w, f) in enumerate(rows):
    left = 0
    for v, c, lab in [(p, INK, "통과"), (w, GRAY, "주의"), (f, SEAL, "실패")]:
        if v:
            ax.barh(i, v, left=left, color=c, height=0.55)
            if v > 2:
                ax.text(left + v / 2, i, f"{lab} {v}", ha="center", va="center", fontsize=17, color="#FFFFFF", weight="bold")
        left += v
    if p == 29:
        ax.text(left + 0.4, i, "주의 2 · 실패 0", ha="left", va="center", fontsize=16, color=INK, weight="bold")
ax.set_yticks([0, 1]); ax.set_yticklabels([r[0] for r in rows], fontsize=16)
ax.set_xlim(0, 37); ax.set_xticks([]); ax.tick_params(axis="y", length=0)
for s in ["top", "right", "left", "bottom"]: ax.spines[s].set_visible(False)
fig.text(0.05, 0.9, "답변 평가 — 사람이 원전과 대조해 판정", fontsize=22, weight="bold", color=INK)
fig.text(0.05, 0.84, "기준: 논지 일치 · 인용 적합성 · 발화자 정합", fontsize=14, color=GRAY)
fig.text(0.2, 0.08, "응답 평균 6.0초 → 5.7초      규칙 위반 재생성 7회 → 2회", fontsize=14, color=INK)
save(fig, "s09-chart-eval.png")
print("ok")
