use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum AppTheme {
 System,
 Light,
 Dark,
 CatppuccinMocha,
 CatppuccinLatte,
 Dracula,
 TokyoNight,
 Nord,
 Gruvbox,
 GruvboxLight,
 OneDark,
 Everforest,
 Kanagawa,
 RosePine,
 SolarizedDark,
 SolarizedLight,
 GithubDark,
 GithubLight,
 Ayu,
 NightOwl,
 Monokai,
 Claude,
 ClaudeLight,
 Codex,
 Cursor,
 Matrix,
}

impl AppTheme {
 pub fn display_name(&self) -> &'static str {
 match self {
 Self::System => "System",
 Self::Light => "Light",
 Self::Dark => "Dark",
 Self::CatppuccinMocha => "Catppuccin Mocha",
 Self::CatppuccinLatte => "Catppuccin Latte",
 Self::Dracula => "Dracula",
 Self::TokyoNight => "Tokyo Night",
 Self::Nord => "Nord",
 Self::Gruvbox => "Gruvbox",
 Self::GruvboxLight => "Gruvbox Light",
 Self::OneDark => "One Dark",
 Self::Everforest => "Everforest",
 Self::Kanagawa => "Kanagawa",
 Self::RosePine => "Rosé Pine",
 Self::SolarizedDark => "Solarized Dark",
 Self::SolarizedLight => "Solarized Light",
 Self::GithubDark => "GitHub Dark",
 Self::GithubLight => "GitHub Light",
 Self::Ayu => "Ayu",
 Self::NightOwl => "Night Owl",
 Self::Monokai => "Monokai",
 Self::Claude => "Claude",
 Self::ClaudeLight => "Claude Light",
 Self::Codex => "Codex",
 Self::Cursor => "Cursor",
 Self::Matrix => "Matrix",
 }
 }

 pub fn detail(&self) -> &'static str {
 match self {
 Self::System => "Follows your system",
 Self::Light => "Light · System accent",
 Self::Dark => "Dark · System accent",
 Self::CatppuccinMocha => "Dark · Mauve",
 Self::CatppuccinLatte => "Light · Mauve",
 Self::Dracula => "Dark · Purple",
 Self::TokyoNight => "Dark · Blue",
 Self::Nord => "Dark · Frost",
 Self::Gruvbox => "Dark · Orange",
 Self::GruvboxLight => "Light · Rust",
 Self::OneDark => "Dark · Blue",
 Self::Everforest => "Dark · Green",
 Self::Kanagawa => "Dark · Wave blue",
 Self::RosePine => "Dark · Rose",
 Self::SolarizedDark => "Dark · Blue",
 Self::SolarizedLight => "Light · Blue",
 Self::GithubDark => "Dark · Blue",
 Self::GithubLight => "Light · Blue",
 Self::Ayu => "Dark · Amber",
 Self::NightOwl => "Dark · Blue",
 Self::Monokai => "Dark · Pink",
 Self::Claude => "Dark · Terracotta",
 Self::ClaudeLight => "Light · Terracotta",
 Self::Codex => "Dark · Magenta",
 Self::Cursor => "Dark · Frost",
 Self::Matrix => "Dark · Green",
 }
 }

 pub fn palette(&self) -> ThemePalette {
 match self {
 Self::System => ThemePalette { scheme: None, accent: None, surface: "1E1E20", success: None, warning: None, danger: None },
 Self::Light => ThemePalette { scheme: Some(ColorScheme::Light), accent: None, surface: "FFFFFF", success: None, warning: None, danger: None },
 Self::Dark => ThemePalette { scheme: Some(ColorScheme::Dark), accent: None, surface: "1E1E20", success: None, warning: None, danger: None },
 Self::CatppuccinMocha => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("CBA6F7"), surface: "1E1E2E", success: Some("A6E3A1"), warning: Some("F9E2AF"), danger: Some("F38BA8") },
 Self::CatppuccinLatte => ThemePalette { scheme: Some(ColorScheme::Light), accent: Some("8839EF"), surface: "EFF1F5", success: Some("40A02B"), warning: Some("DF8E1D"), danger: Some("D20F39") },
 Self::Dracula => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("BD93F9"), surface: "282A36", success: Some("50FA7B"), warning: Some("FFB86C"), danger: Some("FF5555") },
 Self::TokyoNight => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("7AA2F7"), surface: "1A1B26", success: Some("9ECE6A"), warning: Some("E0AF68"), danger: Some("F7768E") },
 Self::Nord => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("88C0D0"), surface: "2E3440", success: Some("A3BE8C"), warning: Some("EBCB8B"), danger: Some("BF616A") },
 Self::Gruvbox => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("FE8019"), surface: "282828", success: Some("B8BB26"), warning: Some("FABD2E"), danger: Some("FB4934") },
 Self::GruvboxLight => ThemePalette { scheme: Some(ColorScheme::Light), accent: Some("AF3A03"), surface: "FBF1C7", success: Some("79740E"), warning: Some("B57614"), danger: Some("9D0006") },
 Self::OneDark => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("61AFEF"), surface: "282C34", success: Some("98C379"), warning: Some("E5C07B"), danger: Some("E06C75") },
 Self::Everforest => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("A7C080"), surface: "2D353B", success: Some("A7C080"), warning: Some("DBBC7F"), danger: Some("E67E80") },
 Self::Kanagawa => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("7E9CD8"), surface: "1F1F28", success: Some("98BB6C"), warning: Some("D7A657"), danger: Some("E82424") },
 Self::RosePine => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("EB6F92"), surface: "191724", success: Some("9CCFD8"), warning: Some("F6C177"), danger: Some("EB6F92") },
 Self::SolarizedDark => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("268BD2"), surface: "002B36", success: Some("859900"), warning: Some("B58900"), danger: Some("DC322F") },
 Self::SolarizedLight => ThemePalette { scheme: Some(ColorScheme::Light), accent: Some("268BD2"), surface: "FDF6E3", success: Some("859900"), warning: Some("B58900"), danger: Some("DC322F") },
 Self::GithubDark => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("4493F8"), surface: "0D1117", success: Some("3FB950"), warning: Some("D29922"), danger: Some("F85149") },
 Self::GithubLight => ThemePalette { scheme: Some(ColorScheme::Light), accent: Some("0969DA"), surface: "FFFFFF", success: Some("1A7F37"), warning: Some("9A6700"), danger: Some("CF222E") },
 Self::Ayu => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("E6B450"), surface: "0F1419", success: Some("AAD94C"), warning: Some("FFB454"), danger: Some("F58572") },
 Self::NightOwl => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("82AAFF"), surface: "011627", success: Some("C5E478"), warning: Some("ECC48D"), danger: Some("EF5350") },
 Self::Monokai => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("F92672"), surface: "272822", success: Some("A6E22E"), warning: Some("FD971F"), danger: Some("F92672") },
 Self::Claude => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("C15F3C"), surface: "1A1816", success: Some("51A556"), warning: Some("C9A227"), danger: Some("D97757") },
 Self::ClaudeLight => ThemePalette { scheme: Some(ColorScheme::Light), accent: Some("C15F3C"), surface: "FAF9F5", success: Some("2E7D32"), warning: Some("9A6700"), danger: Some("B3261E") },
 Self::Codex => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("D946EF"), surface: "101014", success: Some("3FB950"), warning: Some("D29922"), danger: Some("F85149") },
 Self::Cursor => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("88C0D0"), surface: "181818", success: Some("3FA266"), warning: Some("F1B467"), danger: Some("E34671") },
 Self::Matrix => ThemePalette { scheme: Some(ColorScheme::Dark), accent: Some("00E676"), surface: "000000", success: Some("00E676"), warning: Some("FFD600"), danger: Some("FF5252") },
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ColorScheme {
 Light,
 Dark,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemePalette {
 pub scheme: Option<ColorScheme>,
 pub accent: Option<&'static str>,
 pub surface: &'static str,
 pub success: Option<&'static str>,
 pub warning: Option<&'static str>,
 pub danger: Option<&'static str>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemeSpec {
 pub scheme: Option<ColorScheme>,
 pub accent: Option<String>,
 pub surface: String,
 pub success: String,
 pub warning: String,
 pub danger: String,
}
