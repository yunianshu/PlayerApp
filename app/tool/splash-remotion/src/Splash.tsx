import React from 'react';
import { AbsoluteFill, Img, interpolate, spring, useCurrentFrame, useFPS, useVideoConfig } from 'remotion';

// 配色与 AppPalette.light 一致。
const ACCENT = '#5E5CE6';
const ACCENT2 = '#3DD8D0';
const INK = '#1C1C2E';

/**
 * 跑迹 RunTrail 启动动画（2s @30fps，1080x1920）：
 * 0-9 帧：白底 + 应用图标（与 Android 原生启动页完全一致，无缝衔接）
 * 10-40 帧：图标缩小淡出，渐变轨迹划过 + 跑者剪影滑入 + 标题字样弹出
 * 41-59 帧：整体淡出回白底（与首页衔接）
 */
export const Splash: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sp = (f: number) => spring({ frame: f, fps, config: { damping: 200 } });

  // 图标阶段（0-12）：先静止 6 帧后缩小淡出。
  const iconOpacity = interpolate(frame, [8, 18], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const iconScale = interpolate(frame, [8, 18], [1, 0.55], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // 轨迹线（12-45）：一条渐变弧线从左下划到右上。
  const trailProgress = interpolate(frame, [12, 42], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // 跑者剪影沿轨迹滑入（14-36）。
  const runnerIn = sp(frame - 14);
  const runnerX = interpolate(runnerIn, [0, 1], [-320, 470]);
  const runnerY = interpolate(runnerIn, [0, 1], [520, 420]);

  // 标题（24-52）。
  const titleIn = sp(frame - 24);
  const titleY = interpolate(titleIn, [0, 1], [90, 0]);
  const subIn = sp(frame - 30);

  // 收尾淡出（48-60）。
  const fadeOut = interpolate(frame, [48, 59], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill style={{ backgroundColor: '#FFFFFF' }}>
      {/* 阶段一：原生图标（无缝开场） */}
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          opacity: iconOpacity,
          transform: `scale(${iconScale})`,
        }}
      >
        <Img src={require('./icon.png')} style={{ width: 192, height: 192 }} />
      </AbsoluteFill>

      {/* 阶段二：品牌动画 */}
      {frame >= 10 && (
        <AbsoluteFill style={{ opacity: fadeOut }}>
          {/* 渐变轨迹弧线 */}
          <svg width={1080} height={1920} style={{ position: 'absolute' }}>
            <defs>
              <linearGradient id="trail" x1="0%" y1="100%" x2="100%" y2="0%">
                <stop offset="0%" stopColor={ACCENT2} />
                <stop offset="100%" stopColor={ACCENT} />
              </linearGradient>
            </defs>
            <path
              d="M -40 1500 Q 420 1300 620 900 T 900 260"
              fill="none"
              stroke="url(#trail)"
              strokeWidth={14}
              strokeLinecap="round"
              strokeDasharray="1600"
              strokeDashoffset={1600 * (1 - trailProgress)}
            />
            {/* 轨迹终点光点 */}
            {trailProgress >= 0.99 && (
              <circle cx={900} cy={260} r={18} fill={ACCENT} opacity={fadeOut} />
            )}
          </svg>

          {/* 跑者剪影（火柴人风格，沿轨迹） */}
          <svg
            width={240}
            height={280}
            style={{
              position: 'absolute',
              left: runnerX,
              top: runnerY,
              opacity: fadeOut,
            }}
          >
            {/* 简笔跑者：与 App 内 ExerciseFigure 同风格 */}
            <g stroke={ACCENT} strokeWidth={11} strokeLinecap="round" fill="none">
              <circle cx={120} cy={52} r={26} fill={ACCENT} stroke="none" />
              <line x1={120} y1={86} x2={120} y2={158} />
              <line x1={120} y1={104} x2={70} y2={128} />
              <line x1={70} y1={128} x2={62} y2={106} />
              <line x1={120} y1={104} x2={168} y2={92} />
              <line x1={168} y1={92} x2={196} y2={74} />
              <line x1={120} y1={158} x2={76} y2={196} />
              <line x1={76} y1={196} x2={58} y2={240} />
              <line x1={120} y1={158} x2={164} y2={190} />
              <line x1={164} y1={190} x2={150} y2={238} />
            </g>
          </svg>

          {/* 标题区 */}
          <div
            style={{
              position: 'absolute',
              top: 1080,
              width: '100%',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              transform: `translateY(${titleY}px)`,
              opacity: fadeOut,
            }}
          >
            <div
              style={{
                fontSize: 132,
                fontWeight: 800,
                color: INK,
                fontFamily: '"Noto Sans SC", "Microsoft YaHei", sans-serif',
                letterSpacing: 12,
                opacity: titleIn,
              }}
            >
              跑迹
            </div>
            <div
              style={{
                marginTop: 18,
                fontSize: 44,
                fontWeight: 600,
                color: ACCENT,
                fontFamily: 'Arial, sans-serif',
                letterSpacing: 10,
                opacity: subIn,
              }}
            >
              RunTrail
            </div>
            <div
              style={{
                marginTop: 46,
                fontSize: 30,
                color: '#71768A',
                fontFamily: '"Noto Sans SC", "Microsoft YaHei", sans-serif',
                letterSpacing: 6,
                opacity: subIn * 0.9,
              }}
            >
              记 录 每 一 步
            </div>
          </div>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};
