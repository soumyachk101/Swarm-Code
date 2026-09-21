import type { SVGProps } from "react";

export function SwarmCodeWordmark(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 240 240" fill="none" xmlns="http://www.w3.org/2000/svg" {...props}>
      <defs>
        <linearGradient id="swarmcode-bee-g" x1="120" y1="60" x2="120" y2="215" gradientUnits="userSpaceOnUse">
          <stop stopColor="#ffd257" />
          <stop offset="1" stopColor="#e8a512" />
        </linearGradient>
        <clipPath id="swarmcode-bee-c">
          <path d="M120 65C152 65 167 92 167 122C167 160 147 198 120 212C93 198 73 160 73 122C73 92 88 65 120 65Z" />
        </clipPath>
      </defs>
      <g transform="rotate(-8 120 120)">
        <ellipse cx="71" cy="78" rx="40" ry="24" transform="rotate(-38 71 78)" fill="#ffe9ad" stroke="#d99a1c" strokeWidth="6" />
        <ellipse cx="169" cy="78" rx="40" ry="24" transform="rotate(38 169 78)" fill="#ffe9ad" stroke="#d99a1c" strokeWidth="6" />
        <path d="M112 66C108 52 105 43 99 35" stroke="#171106" strokeWidth="8" strokeLinecap="round" fill="none" />
        <path d="M128 66C132 52 135 43 141 35" stroke="#171106" strokeWidth="8" strokeLinecap="round" fill="none" />
        <circle cx="98" cy="33" r="7" fill="#171106" />
        <circle cx="142" cy="33" r="7" fill="#171106" />
        <path d="M120 65C152 65 167 92 167 122C167 160 147 198 120 212C93 198 73 160 73 122C73 92 88 65 120 65Z" fill="url(#swarmcode-bee-g)" />
        <g clipPath="url(#swarmcode-bee-c)" fill="#171106">
          <rect x="60" y="95" width="120" height="23" />
          <rect x="60" y="132" width="120" height="23" />
          <rect x="60" y="169" width="120" height="23" />
        </g>
      </g>
    </svg>
  );
}

