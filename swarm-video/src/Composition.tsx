import React from "react";
import { AbsoluteFill, useCurrentFrame, Sequence, spring, Composition, CalculateMetadataFunction } from "remotion";
import "./index.css";

const COLORS = {
  bg: "#050510", bgAlt: "#0a0a1e",
  primary: "#00e5ff", secondary: "#7c3aed", accent: "#ff2d55",
  textPrimary: "#ffffff", textSecondary: "#a0a0c0",
  orange: "#ffaa00", green: "#00ff88", pink: "#ff66cc",
};

const easeOutExpo = (t: number) => (t === 1 ? 1 : 1 - Math.pow(2, -10 * t));

const CinematicIntro = () => {
  const frame = useCurrentFrame();
  const particles = Array.from({ length: 50 }).map((_, i) => {
    const sf = (i * 7) % 30;
    const t = Math.max(0, frame - sf) / 100;
    const x = easeOutExpo(Math.min(1, t)) * 1920 * (((i * 73 + 31) % 100) / 100);
    const y = easeOutExpo(Math.min(1, t)) * 1080 * (((i * 97 + 53) % 100) / 100);
    const sz = (i % 5) + 1;
    const colors = [COLORS.primary, COLORS.secondary, COLORS.accent];
    const c = colors[i % 3];
    const a = easeOutExpo(Math.max(0, Math.min(1, (frame - sf - 40) / 40)));
    return <div key={i} style={{ position: "absolute", left: x, top: y, width: sz, height: sz, borderRadius: "50%", background: c, opacity: a * 0.8, boxShadow: `0 0 ${sz * 3}px ${c}` }} />;
  });
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 50%, #0f0f2e 0%, ${COLORS.bg} 70%)`, fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif", overflow: "hidden" }}>
      <div style={{ position: "relative", zIndex: 10, width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center" }}>
        <div style={{ fontSize: 14, letterSpacing: "0.3em", color: COLORS.primary, marginBottom: 40, textTransform: "uppercase", fontWeight: 600, opacity: easeOutExpo(Math.min(1, frame / 80)), transform: `translateY(${(1 - easeOutExpo(Math.min(1, frame / 80))) * 30}px)` }}>Introducing the Future of Coding</div>
        <h1 style={{ fontSize: 110, fontWeight: 900, color: COLORS.textPrimary, letterSpacing: "-0.03em", lineHeight: 0.95, textAlign: "center", opacity: easeOutExpo(Math.min(1, (frame - 20) / 80)), transform: `translateY(${(1 - easeOutExpo(Math.min(1, (frame - 20) / 80))) * 40}px)` }}><span style={{ background: `linear-gradient(135deg, ${COLORS.primary} 0%, ${COLORS.secondary} 100%)`, WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent", backgroundClip: "text" }}>Swarm Code</span></h1>
        <div style={{ fontSize: 24, color: COLORS.textSecondary, marginTop: 40, letterSpacing: "0.1em", opacity: easeOutExpo(Math.min(1, (frame - 60) / 60)), transform: `translateY(${(1 - easeOutExpo(Math.min(1, (frame - 60) / 60))) * 20}px)` }}>AI-Powered Multi-Agent Coding Intelligence</div>
        <div style={{ width: 200, height: 2, background: `linear-gradient(90deg, transparent, ${COLORS.primary}, ${COLORS.secondary}, transparent)`, marginTop: 60, opacity: easeOutExpo(Math.min(1, (frame - 90) / 40)) }} />
      </div>
      {particles}
    </AbsoluteFill>
  );
};

const BrandReveal = () => {
  const frame = useCurrentFrame();
  const logoScale = spring({ frame, fps: 30, config: { damping: 15, stiffness: 80 } });
  return (
    <AbsoluteFill style={{ background: `linear-gradient(135deg, #0f0f2e 0%, ${COLORS.bg} 100%)`, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif" }}>
      <div style={{ width: 180, height: 180, borderRadius: 40, background: `linear-gradient(135deg, ${COLORS.primary} 0%, ${COLORS.secondary} 100%)`, display: "flex", justifyContent: "center", alignItems: "center", transform: `scale(${logoScale})`, boxShadow: `0 0 80px ${COLORS.primary}40, 0 0 160px ${COLORS.secondary}30`, marginBottom: 60 }}>
        <svg width="90" height="90" viewBox="0 0 100 100" fill="none"><path d="M50 10 L85 30 L85 70 L50 90 L15 70 L15 30 Z" stroke="white" strokeWidth="3" fill="none" /><circle cx="50" cy="50" r="20" fill="white" /><circle cx="50" cy="50" r="8" fill={COLORS.primary} /></svg>
      </div>
      <h1 style={{ fontSize: 80, fontWeight: 900, color: COLORS.textPrimary, letterSpacing: "-0.02em", opacity: easeOutExpo(Math.min(1, (frame - 15) / 70)), transform: `translateY(${(1 - easeOutExpo(Math.min(1, (frame - 15) / 70))) * 50}px)` }}>Swarm Code</h1>
      <div style={{ fontSize: 22, color: COLORS.textSecondary, marginTop: 24, letterSpacing: "0.15em", textTransform: "uppercase", opacity: easeOutExpo(Math.min(1, (frame - 30) / 50)), transform: `translateY(${(1 - easeOutExpo(Math.min(1, (frame - 30) / 50))) * 20}px)` }}>Built by Soumya Chakraborty · MIT License</div>
      <div style={{ display: "flex", gap: 40, marginTop: 80, opacity: easeOutExpo(Math.min(1, (frame - 80) / 60)), transform: `translateY(${(1 - easeOutExpo(Math.min(1, (frame - 80) / 60))) * 30}px)` }}>
        {["macOS Native", "AI-Powered", "Multi-Agent", "Open Source"].map((tag, i) => (<div key={tag} style={{ padding: "12px 28px", border: `1px solid ${COLORS.primary}40`, borderRadius: 100, color: COLORS.primary, fontSize: 14, letterSpacing: "0.1em", background: `${COLORS.primary}10`, opacity: easeOutExpo(Math.min(1, (frame - (90 + i * 15)) / 30)) }}>{tag}</div>))}
      </div>
    </AbsoluteFill>
  );
};

const ProblemStatement = () => {
  const frame = useCurrentFrame();
  const painPoints = [{ icon: "⏱", text: "Hours lost to context switching" }, { icon: "🔄", text: "Endless code refactoring loops" }, { icon: "🧠", text: "Manual plumbing between tools" }, { icon: "📂", text: "Files scattered across editors" }];
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at center, #14008f 0%, ${COLORS.bg} 100%)`, fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif", padding: 80, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center" }}>
      <div style={{ textAlign: "center", marginBottom: 60, opacity: easeOutExpo(Math.min(1, frame / 60)) }}>
        <div style={{ fontSize: 18, color: COLORS.accent, letterSpacing: "0.3em", marginBottom: 20, textTransform: "uppercase" }}>The Problem</div>
        <h2 style={{ fontSize: 64, fontWeight: 800, color: COLORS.textPrimary, lineHeight: 1.1, maxWidth: 1400, margin: "0 auto" }}>Modern coding is fragmented.<br /><span style={{ color: COLORS.accent }}>Your focus shouldn't be.</span></h2>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 32, width: "100%", maxWidth: 1400 }}>
        {painPoints.map((point, i) => { const delay = 60 + i * 25; const opacity = easeOutExpo(Math.min(1, Math.max(0, (frame - delay) / 40))); return (<div key={i} style={{ background: "rgba(255,45,85,0.05)", border: `1px solid ${COLORS.accent}30`, borderRadius: 20, padding: 40, opacity, backdropFilter: "blur(10px)" }}><div style={{ fontSize: 48, marginBottom: 20 }}>{point.icon}</div><div style={{ fontSize: 28, color: COLORS.textPrimary, fontWeight: 500 }}>{point.text}</div></div>); })}
      </div>
    </AbsoluteFill>
  );
};

const SolutionReveal = () => {
  const frame = useCurrentFrame();
  const agents = [{ name: "Hydra", role: "Multi-Head Strategy", color: COLORS.primary }, { name: "Titan", role: "Heavy Computation", color: COLORS.secondary }, { name: "Apex", role: "Code Analysis", color: COLORS.accent }, { name: "Nexus", role: "State Management", color: COLORS.orange }];
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 30% 50%, #0a0f1e 0%, ${COLORS.bg} 80%)`, fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: 80 }}>
      <div style={{ textAlign: "center", marginBottom: 60, opacity: easeOutExpo(Math.min(1, frame / 60)) }}>
        <div style={{ fontSize: 18, color: COLORS.primary, letterSpacing: "0.3em", marginBottom: 20, textTransform: "uppercase" }}>The Solution</div>
        <h2 style={{ fontSize: 68, fontWeight: 900, color: COLORS.textPrimary, lineHeight: 1.1 }}>One App.<br /><span style={{ background: `linear-gradient(135deg, ${COLORS.primary}, ${COLORS.secondary})`, WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent", backgroundClip: "text" }}>Infinite Agents.</span></h2>
        <p style={{ fontSize: 26, color: COLORS.textSecondary, marginTop: 30, maxWidth: 900, margin: "30px auto 0" }}>Coordinated AI swarms that think, plan, and execute together.</p>
      </div>
      <div style={{ display: "flex", gap: 40, justifyContent: "center", flexWrap: "wrap", maxWidth: 1500 }}>
        {agents.map((agent, i) => { const delay = 50 + i * 30; const progress = easeOutExpo(Math.min(1, Math.max(0, (frame - delay) / 50))); return (<div key={agent.name} style={{ width: 280, height: 340, background: `linear-gradient(135deg, ${agent.color}15 0%, transparent 100%)`, border: `1px solid ${agent.color}40`, borderRadius: 24, padding: 40, opacity: progress, transform: `translateY(${(1 - progress) * 40}px)`, position: "relative", overflow: "hidden" }}><div style={{ position: "absolute", top: -40, right: -40, width: 120, height: 120, borderRadius: "50%", background: `radial-gradient(circle, ${agent.color}30, transparent)`, filter: "blur(30px)" }} /><div style={{ fontSize: 48, marginBottom: 20 }}>◉</div><div style={{ fontSize: 32, fontWeight: 800, color: agent.color, marginBottom: 12 }}>{agent.name}</div><div style={{ fontSize: 16, color: COLORS.textSecondary }}>{agent.role}</div></div>); })}
      </div>
    </AbsoluteFill>
  );
};

const FeatureShowcase = () => {
  const frame = useCurrentFrame();
  const features = [{ num: "01", title: "Multi-Agent Swarms", desc: "Multiple AI agents coordinated to solve complex tasks in parallel.", color: COLORS.primary }, { num: "02", title: "Native macOS Experience", desc: "Built with SwiftUI, Metal acceleration, native terminal integration.", color: COLORS.secondary }, { num: "03", title: "MCP Server Support", desc: "Connect external tools through Model Context Protocol.", color: COLORS.accent }, { num: "04", title: "Hydra Head Profiles", desc: "Switch between AI model configurations on the fly.", color: COLORS.orange }, { num: "05", title: "Real-Time Streaming", desc: "Watch AI responses stream as agents collaborate.", color: COLORS.green }, { num: "06", title: "Session Persistence", desc: "Full conversation history and project memory across restarts.", color: COLORS.pink }];
  return (
    <AbsoluteFill style={{ background: COLORS.bg, fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif", padding: 80, display: "flex", flexDirection: "column", justifyContent: "center" }}>
      <div style={{ marginBottom: 60 }}><div style={{ fontSize: 18, color: COLORS.primary, letterSpacing: "0.3em", marginBottom: 16, textTransform: "uppercase" }}>Features</div><h2 style={{ fontSize: 58, fontWeight: 900, color: COLORS.textPrimary }}>Everything you need.<br /><span style={{ color: COLORS.textSecondary }}>Nothing you don't.</span></h2></div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gridTemplateRows: "repeat(2, 1fr)", gap: 24, width: "100%" }}>
        {features.map((feature, i) => { const delay = 20 + i * 20; const progress = easeOutExpo(Math.min(1, Math.max(0, (frame - delay) / 40))); return (<div key={i} style={{ background: `linear-gradient(135deg, ${feature.color}10 0%, transparent 60%)`, border: `1px solid ${feature.color}25`, borderRadius: 20, padding: 36, opacity: progress, transform: `translateY(${(1 - progress) * 30}px)`, position: "relative", overflow: "hidden" }}><div style={{ fontSize: 14, color: feature.color, fontWeight: 700, letterSpacing: "0.15em", marginBottom: 12 }}>{feature.num}</div><div style={{ fontSize: 26, fontWeight: 700, color: COLORS.textPrimary, marginBottom: 12, lineHeight: 1.2 }}>{feature.title}</div><div style={{ fontSize: 16, color: COLORS.textSecondary, lineHeight: 1.5 }}>{feature.desc}</div></div>); })}
      </div>
    </AbsoluteFill>
  );
};

const StatsImpact = () => {
  const frame = useCurrentFrame();
  const stats = [{ number: "10×", label: "Faster Development", sub: "Parallel AI agents" }, { number: "99%", label: "Accuracy Rate", sub: "Context-aware reasoning" }, { number: "< 1s", label: "Agent Response", sub: "Real-time streaming" }, { number: "∞", label: "Possibilities", sub: "Extensible via MCP" }];
  return (
    <AbsoluteFill style={{ background: `linear-gradient(180deg, ${COLORS.bgAlt} 0%, ${COLORS.bg} 100%)`, fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: 80 }}>
      <div style={{ textAlign: "center", marginBottom: 80, opacity: easeOutExpo(Math.min(1, frame / 60)) }}><div style={{ fontSize: 18, color: COLORS.primary, letterSpacing: "0.3em", marginBottom: 20, textTransform: "uppercase" }}>By the Numbers</div><h2 style={{ fontSize: 56, fontWeight: 900, color: COLORS.textPrimary }}>Performance that <span style={{ color: COLORS.primary }}>speaks</span></h2></div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 40, width: "100%", maxWidth: 1600 }}>
        {stats.map((stat, i) => { const delay = 40 + i * 25; const progress = easeOutExpo(Math.min(1, Math.max(0, (frame - delay) / 50))); return (<div key={i} style={{ textAlign: "center", opacity: progress, transform: `translateY(${(1 - progress) * 40}px)` }}><div style={{ fontSize: 90, fontWeight: 900, background: `linear-gradient(135deg, ${COLORS.primary}, ${COLORS.secondary})`, WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent", backgroundClip: "text", lineHeight: 1 }}>{stat.number}</div><div style={{ fontSize: 22, color: COLORS.textPrimary, fontWeight: 700, marginTop: 20, marginBottom: 8 }}>{stat.label}</div><div style={{ fontSize: 14, color: COLORS.textSecondary }}>{stat.sub}</div></div>); })}
      </div>
    </AbsoluteFill>
  );
};

const SwarmRings: React.FC<{ delay: number; size: number }> = ({ delay, size }) => {
  const frame = useCurrentFrame();
  const lf = frame - delay;
  if (lf < 0) return null;
  const scale = easeOutExpo(Math.min(1, lf / 40));
  const opacity = easeOutExpo(Math.min(1, lf / 30));
  return <div style={{ position: "absolute", width: size, height: size, borderRadius: "50%", border: `2px solid ${COLORS.primary}60`, opacity, transform: `scale(${scale})` }} />;
};

const ClosingCTA: React.FC = () => {
  const frame = useCurrentFrame();
  const mainOpacity = easeOutExpo(Math.min(1, frame / 80));
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 50%, #0f0f2e 0%, ${COLORS.bg} 70%)`, fontFamily: "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", position: "relative", overflow: "hidden" }}>
      {[0, 1, 2, 3].map((i) => <SwarmRings key={i} delay={i * 15} size={300 + i * 80} />)}
      <div style={{ position: "relative", zIndex: 10, textAlign: "center", padding: 80 }}>
        <div style={{ fontSize: 16, color: COLORS.primary, letterSpacing: "0.4em", marginBottom: 30, textTransform: "uppercase", opacity: mainOpacity, transform: `translateY(${(1 - mainOpacity) * 20}px)` }}>The Future of Coding is Here</div>
        <h2 style={{ fontSize: 100, fontWeight: 900, color: COLORS.textPrimary, lineHeight: 1, marginBottom: 40, opacity: mainOpacity, transform: `translateY(${(1 - mainOpacity) * 30}px)` }}><span style={{ background: `linear-gradient(135deg, ${COLORS.primary} 0%, ${COLORS.secondary} 100%)`, WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent", backgroundClip: "text" }}>Swarm Code</span></h2>
        <div style={{ fontSize: 24, color: COLORS.textSecondary, maxWidth: 800, margin: "0 auto 50px", opacity: easeOutExpo(Math.min(1, Math.max(0, (frame - 60) / 60))) }}>Code faster. Think smarter. Build together.</div>
        <div style={{ display: "inline-flex", padding: "18px 56px", background: `linear-gradient(135deg, ${COLORS.primary}, ${COLORS.secondary})`, color: COLORS.bg, fontSize: 18, fontWeight: 800, letterSpacing: "0.15em", borderRadius: 100, textTransform: "uppercase", boxShadow: `0 0 40px ${COLORS.primary}40`, opacity: easeOutExpo(Math.min(1, Math.max(0, (frame - 100) / 60))), transform: `translateY(${(1 - easeOutExpo(Math.min(1, Math.max(0, (frame - 100) / 60)))) * 20}px)` }}>Download Swarm Code</div>
        <div style={{ marginTop: 40, fontSize: 14, color: COLORS.textSecondary, opacity: easeOutExpo(Math.min(1, Math.max(0, (frame - 150) / 50))) }}>by Soumya Chakraborty · MIT License · Open Source</div>
      </div>
    </AbsoluteFill>
  );
};

const MasterComposition: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: COLORS.bg }}>
      <Sequence from={0} durationInFrames={270}><CinematicIntro /></Sequence>
      <Sequence from={270} durationInFrames={300}><BrandReveal /></Sequence>
      <Sequence from={570} durationInFrames={360}><ProblemStatement /></Sequence>
      <Sequence from={930} durationInFrames={420}><SolutionReveal /></Sequence>
      <Sequence from={1350} durationInFrames={600}><FeatureShowcase /></Sequence>
      <Sequence from={1950} durationInFrames={300}><StatsImpact /></Sequence>
      <Sequence from={2250} durationInFrames={270}><ClosingCTA /></Sequence>
    </AbsoluteFill>
  );
};

const calculateMetadata: CalculateMetadataFunction<{}> = async () => {
  return {};
};

export const MyComposition = () => {
  return (
    <>
      <Composition id="SwarmCodeCinematic" component={MasterComposition} durationInFrames={2520} fps={30} width={1920} height={1080} calculateMetadata={calculateMetadata} />
      <Composition id="SwarmAICinematic" component={MasterComposition} durationInFrames={2520} fps={30} width={1920} height={1080} calculateMetadata={calculateMetadata} />
    </>
  );
};

export { MasterComposition };
