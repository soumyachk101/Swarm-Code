import { useState, useCallback } from "react";
import { ArrowUpRightIcon, XIcon, SparklesIcon, LayersIcon, SlidersIcon } from "lucide-react";
import { SettingsPageContainer } from "./settingsLayout";

const SWARM_CODE_VERSION = "1.8.0";
const SWARM_CODE_BUILD = "29";

export function AboutHeaderPills() {
  return (
    <div className="flex items-center gap-2">
      {/* Version pill */}
      <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/[0.06] hover:bg-white/[0.09] border border-white/10 text-xs font-medium text-foreground transition-colors shadow-xs select-none">
        <img
          src="/swarmcode-icon.webp"
          alt="Swarm Code"
          className="size-3.5 rounded-[3px] object-cover shrink-0"
        />
        <span>v{SWARM_CODE_VERSION}</span>
      </div>

      {/* Up to date pill */}
      <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/[0.06] hover:bg-white/[0.09] border border-white/10 text-xs font-medium text-foreground transition-colors shadow-xs select-none">
        <svg className="size-3.5 text-emerald-400 fill-current shrink-0" viewBox="0 0 24 24">
          <path
            fillRule="evenodd"
            d="M8.6 1.8a2.5 2.5 0 0 1 3.5-1.1l.6.3a2.5 2.5 0 0 0 2.6 0l.6-.3a2.5 2.5 0 0 1 3.5 1.1l.3.6a2.5 2.5 0 0 0 2.2 1.3l.7.1a2.5 2.5 0 0 1 2.3 2.8l-.1.7a2.5 2.5 0 0 0 1 2.4l.5.5a2.5 2.5 0 0 1 0 3.7l-.5.5a2.5 2.5 0 0 0-1 2.4l.1.7a2.5 2.5 0 0 1-2.3 2.8l-.7.1a2.5 2.5 0 0 0-2.2 1.3l-.3.6a2.5 2.5 0 0 1-3.5 1.1l-.6-.3a2.5 2.5 0 0 0-2.6 0l-.6.3a2.5 2.5 0 0 1-3.5-1.1l-.3-.6a2.5 2.5 0 0 0-2.2-1.3l-.7-.1a2.5 2.5 0 0 1-2.3-2.8l.1-.7a2.5 2.5 0 0 0-1-2.4l-.5-.5a2.5 2.5 0 0 1 0-3.7l.5-.5a2.5 2.5 0 0 0 1-2.4l-.1-.7a2.5 2.5 0 0 1 2.3-2.8l.7-.1a2.5 2.5 0 0 0 2.2-1.3l.3-.6ZM16.7 8.7a1 1 0 0 0-1.4-1.4L10.5 12l-1.8-1.8a1 1 0 0 0-1.4 1.4l2.5 2.5a1 1 0 0 0 1.4 0l5.5-5.4Z"
            clipRule="evenodd"
          />
        </svg>
        <span>Up to date</span>
      </div>
    </div>
  );
}

export function AboutSettingsPanel() {
  const [isTourOpen, setIsTourOpen] = useState(false);
  const [isLicensesOpen, setIsLicensesOpen] = useState(false);
  const [activeLicenseTab, setActiveLicenseTab] = useState<"mit" | "notices" | "trademarks">("mit");
  const [isCheckingUpdate, setIsCheckingUpdate] = useState(false);
  const [updateStatus, setUpdateStatus] = useState(
    "Swarm Code checks GitHub for new versions a few times a day. Checked now.",
  );

  const handleCheckUpdate = useCallback(() => {
    setIsCheckingUpdate(true);
    setUpdateStatus("Asking GitHub for the latest release…");
    setTimeout(() => {
      setIsCheckingUpdate(false);
      setUpdateStatus("Swarm Code checks GitHub for new versions a few times a day. Checked just now.");
    }, 1200);
  }, []);

  return (
    <SettingsPageContainer className="pb-16 max-w-3xl">
      <div className="space-y-6">
        {/* Main App Card */}
        <div className="rounded-2xl border border-border/60 bg-card/40 divide-y divide-border/50 shadow-xs/5 overflow-hidden">
          {/* App Header Row */}
          <div className="flex items-center gap-4 p-4 sm:p-5">
            <img
              src="/swarmcode-icon.webp"
              alt="Swarm Code"
              className="size-14 rounded-2xl object-cover shrink-0 shadow-sm border border-white/10"
            />
            <div className="min-w-0">
              <h2 className="text-base font-semibold text-foreground">Swarm Code</h2>
              <p className="text-xs text-muted-foreground mt-0.5">
                Version {SWARM_CODE_VERSION} ({SWARM_CODE_BUILD})
              </p>
            </div>
          </div>

          {/* Welcome tour row */}
          <div className="flex items-center justify-between gap-4 px-4 py-3 sm:px-5 sm:py-3.5">
            <div className="min-w-0 flex-1">
              <div className="text-[13px] font-medium text-foreground">Welcome tour</div>
              <div className="text-xs text-muted-foreground mt-0.5">
                The slideshow from the first launch: Hydra, the effort slider, panels and themes.
              </div>
            </div>
            <button
              type="button"
              onClick={() => setIsTourOpen(true)}
              className="rounded-full bg-[#b070ff] hover:bg-[#9f5af5] active:bg-[#8e45e8] text-white px-3.5 py-1 text-xs font-semibold transition-colors shadow-xs shrink-0 cursor-pointer"
            >
              Show
            </button>
          </div>

          {/* Software update row */}
          <div className="flex items-center justify-between gap-4 px-4 py-3 sm:px-5 sm:py-3.5">
            <div className="min-w-0 flex-1">
              <div className="text-[13px] font-medium text-foreground">Software update</div>
              <div className="text-xs text-muted-foreground mt-0.5">{updateStatus}</div>
            </div>
            <button
              type="button"
              onClick={handleCheckUpdate}
              disabled={isCheckingUpdate}
              className="rounded-full bg-[#b070ff] hover:bg-[#9f5af5] active:bg-[#8e45e8] disabled:opacity-60 text-white px-3.5 py-1 text-xs font-semibold transition-colors shadow-xs shrink-0 cursor-pointer"
            >
              {isCheckingUpdate ? "Checking…" : "Check now"}
            </button>
          </div>

          {/* Tagline row */}
          <div className="px-4 py-3.5 sm:px-5 sm:py-4">
            <p className="text-[13px] text-foreground font-normal leading-relaxed">
              The coding app by Soumya Chakraborty: a native home for your coding agents, built in
              Swift with Liquid Glass.
            </p>
          </div>

          {/* License notice footer */}
          <div className="px-4 py-3 sm:px-5 sm:py-3.5">
            <p className="text-xs text-muted-foreground">
              Swarm Code and SwiftTerm are MIT licensed.
            </p>
          </div>
        </div>

        {/* Section Heading: Credits */}
        <div>
          <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5 mb-2.5">
            Credits
          </h3>

          {/* Credits Card */}
          <div className="rounded-2xl border border-border/60 bg-card/40 divide-y divide-border/50 shadow-xs/5 overflow-hidden">
            {/* Made by Soumya Chakraborty */}
            <div className="flex items-center justify-between gap-4 px-4 py-3.5 sm:px-5 sm:py-4">
              <div className="flex items-center gap-3.5 min-w-0">
                <img
                  src="/swarmcode-icon.webp"
                  alt="Swarm Code"
                  className="size-10 rounded-xl object-cover shrink-0 shadow-xs border border-white/10"
                />
                <div className="min-w-0">
                  <div className="text-[13px] font-semibold text-foreground">
                    Made by Soumya Chakraborty
                  </div>
                  <div className="text-xs text-muted-foreground mt-0.5">
                    Swarm Code is a coding app by Soumya Chakraborty for Mac.
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-3.5 shrink-0">
                <CreditLink href="https://swarmcode.vercel.app" label="Website" />
                <CreditLink href="https://github.com/soumyachk101" label="GitHub" />
              </div>
            </div>

            {/* Website */}
            <CreditRow
              title="Website"
              detail="swarmcode.vercel.app"
              action={
                <CreditLink href="https://swarmcode.vercel.app" label="Open website" />
              }
            />

            {/* GitHub Profile */}
            <CreditRow
              title="GitHub Profile"
              detail="Soumya Chakraborty on GitHub (@soumyachk101)"
              action={
                <CreditLink href="https://github.com/soumyachk101" label="@soumyachk101" />
              }
            />

            {/* Source code */}
            <CreditRow
              title="Source code"
              detail="Swarm Code repository on GitHub."
              action={
                <CreditLink
                  href="https://github.com/soumyachk101/Swarm-Code"
                  label="soumyachk101/Swarm-Code"
                />
              }
            />

            {/* Releases */}
            <CreditRow
              title="Releases"
              detail="Latest release builds and changelog."
              action={
                <CreditLink
                  href="https://github.com/soumyachk101/Swarm-Code-Release/releases"
                  label="Releases"
                />
              }
            />

            {/* Working indicators */}
            <CreditRow
              title="Working indicators"
              detail="Ported from Zeron by Wing, MIT License."
              action={
                <CreditLink href="https://github.com/zeronsh/zeron" label="zeronsh/zeron" />
              }
            />

            {/* Terminal */}
            <CreditRow
              title="Terminal"
              detail="SwiftTerm by Miguel de Icaza, MIT License."
              action={
                <CreditLink
                  href="https://github.com/migueldeicaza/SwiftTerm"
                  label="SwiftTerm"
                />
              }
            />

            {/* Welcome tour */}
            <CreditRow
              title="Welcome tour"
              detail="Ported from TourKit by Ram Patra, MIT License."
              action={
                <CreditLink href="https://github.com/rampatra/TourKit" label="rampatra/TourKit" />
              }
            />

            {/* Licenses */}
            <CreditRow
              title="Licenses"
              detail="MIT, with the notices for what the app builds on."
              action={
                <button
                  type="button"
                  onClick={() => setIsLicensesOpen(true)}
                  className="rounded-full bg-[#b070ff] hover:bg-[#9f5af5] active:bg-[#8e45e8] text-white px-3.5 py-1 text-xs font-semibold transition-colors shadow-xs shrink-0 cursor-pointer"
                >
                  Show
                </button>
              }
            />
          </div>
        </div>
      </div>

      {/* Welcome Tour Dialog */}
      {isTourOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-150">
          <div className="w-full max-w-lg rounded-2xl border border-border/80 bg-card p-6 shadow-xl space-y-5">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <img
                  src="/swarmcode-icon.webp"
                  alt="Swarm Code"
                  className="size-8 rounded-lg object-cover"
                />
                <div>
                  <h3 className="text-base font-semibold text-foreground">Welcome to Swarm Code</h3>
                  <p className="text-xs text-muted-foreground">The slideshow from first launch</p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsTourOpen(false)}
                className="rounded-lg p-1.5 text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                <XIcon className="size-4" />
              </button>
            </div>

            <div className="space-y-3 text-sm">
              <div className="rounded-xl border border-border/50 bg-muted/20 p-4 space-y-1.5">
                <div className="flex items-center gap-2 font-medium text-foreground">
                  <LayersIcon className="size-4 text-[#b070ff]" />
                  <span>Hydra Multi-Agent Heads</span>
                </div>
                <p className="text-xs text-muted-foreground leading-relaxed">
                  Run a lead agent alongside a team of parallel helper heads that edit and build
                  directly in their isolated git worktrees.
                </p>
              </div>

              <div className="rounded-xl border border-border/50 bg-muted/20 p-4 space-y-1.5">
                <div className="flex items-center gap-2 font-medium text-foreground">
                  <SlidersIcon className="size-4 text-[#b070ff]" />
                  <span>Effort Slider</span>
                </div>
                <p className="text-xs text-muted-foreground leading-relaxed">
                  Control agent reasoning depth on the fly, from light touch code edits to deep
                  architectural investigations.
                </p>
              </div>

              <div className="rounded-xl border border-border/50 bg-muted/20 p-4 space-y-1.5">
                <div className="flex items-center gap-2 font-medium text-foreground">
                  <SparklesIcon className="size-4 text-[#b070ff]" />
                  <span>Liquid Glass & Themes</span>
                </div>
                <p className="text-xs text-muted-foreground leading-relaxed">
                  A fluid, translucent desktop interface crafted with care, complete with vibrant
                  light and dark palettes.
                </p>
              </div>
            </div>

            <div className="flex justify-end pt-1">
              <button
                type="button"
                onClick={() => setIsTourOpen(false)}
                className="rounded-full bg-[#b070ff] hover:bg-[#9f5af5] text-white px-5 py-1.5 text-xs font-semibold shadow-sm transition-colors cursor-pointer"
              >
                Got it
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Licenses Dialog */}
      {isLicensesOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-150">
          <div className="w-full max-w-xl rounded-2xl border border-border/80 bg-card p-6 shadow-xl space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-base font-semibold text-foreground">Licenses & Notices</h3>
                <p className="text-xs text-muted-foreground">What Swarm Code builds on</p>
              </div>
              <button
                type="button"
                onClick={() => setIsLicensesOpen(false)}
                className="rounded-lg p-1.5 text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                <XIcon className="size-4" />
              </button>
            </div>

            {/* Tabs */}
            <div className="flex gap-2 border-b border-border/50 pb-2">
              <button
                type="button"
                onClick={() => setActiveLicenseTab("mit")}
                className={`text-xs px-3 py-1 rounded-full font-medium transition-colors ${
                  activeLicenseTab === "mit"
                    ? "bg-[#b070ff] text-white"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted/40"
                }`}
              >
                Swarm Code (MIT)
              </button>
              <button
                type="button"
                onClick={() => setActiveLicenseTab("notices")}
                className={`text-xs px-3 py-1 rounded-full font-medium transition-colors ${
                  activeLicenseTab === "notices"
                    ? "bg-[#b070ff] text-white"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted/40"
                }`}
              >
                Third-party notices
              </button>
              <button
                type="button"
                onClick={() => setActiveLicenseTab("trademarks")}
                className={`text-xs px-3 py-1 rounded-full font-medium transition-colors ${
                  activeLicenseTab === "trademarks"
                    ? "bg-[#b070ff] text-white"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted/40"
                }`}
              >
                Trademarks
              </button>
            </div>

            {/* Tab content */}
            <div className="h-64 overflow-y-auto rounded-xl border border-border/40 bg-muted/20 p-4 font-mono text-xs text-muted-foreground whitespace-pre-wrap leading-relaxed">
              {activeLicenseTab === "mit" && (
                <>
                  MIT License{"\n\n"}
                  Copyright (c) 2026 Soumya Chakraborty{"\n\n"}
                  Permission is hereby granted, free of charge, to any person obtaining a copy
                  of this software and associated documentation files (the "Software"), to deal
                  in the Software without restriction, including without limitation the rights
                  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
                  copies of the Software, and to permit persons to whom the Software is
                  furnished to do so, subject to the following conditions:{"\n\n"}
                  The above copyright notice and this permission notice shall be included in all
                  copies or substantial portions of the Software.{"\n\n"}
                  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
                  SOFTWARE.
                </>
              )}

              {activeLicenseTab === "notices" && (
                <>
                  Swarm Code builds on exceptional open-source software:{"\n\n"}
                  • SwiftTerm — Miguel de Icaza (MIT License){"\n"}
                  • Zeron — Wing (MIT License){"\n"}
                  • TourKit — Ram Patra (MIT License){"\n"}
                  • Effect-TS — Effectful Technologies (MIT License){"\n"}
                  • React & Vite+ — Meta & VoidZero (MIT License){"\n"}
                  • TailwindCSS & Lucide Icons — MIT License{"\n\n"}
                  Visit Settings &gt; Open Source Licenses for the comprehensive manifest of all
                  bundled components and packages.
                </>
              )}

              {activeLicenseTab === "trademarks" && (
                <>
                  Swarm Code Trademark Policy{"\n\n"}
                  "Swarm Code" and the Swarm Code bee logo are trademarks of Soumya Chakraborty.{"\n\n"}
                  All other product names, logos, and brands mentioned are property of their
                  respective owners.
                </>
              )}
            </div>

            <div className="flex justify-end pt-1">
              <button
                type="button"
                onClick={() => setIsLicensesOpen(false)}
                className="rounded-full bg-[#b070ff] hover:bg-[#9f5af5] text-white px-5 py-1.5 text-xs font-semibold shadow-sm transition-colors cursor-pointer"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </SettingsPageContainer>
  );
}

function CreditRow({
  title,
  detail,
  action,
}: {
  title: string;
  detail: string;
  action: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4 px-4 py-3 sm:px-5 sm:py-3.5">
      <div className="min-w-0 flex-1">
        <div className="text-[13px] font-medium text-foreground">{title}</div>
        <div className="text-xs text-muted-foreground mt-0.5">{detail}</div>
      </div>
      <div className="shrink-0">{action}</div>
    </div>
  );
}

function CreditLink({ href, label }: { href: string; label: string }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer noopener"
      className="inline-flex items-center gap-1 text-xs font-medium text-[#b070ff] hover:text-[#c48dff] transition-colors group cursor-pointer"
    >
      <span>{label}</span>
      <ArrowUpRightIcon className="size-3 transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 shrink-0" />
    </a>
  );
}

