//! `[pr]` (items 11, 24, 115).

use serde::Deserialize;

/// Item 11, rule 3: above `aviso_linhas` product lines the summary suggests a
/// split. Item 24:
/// `forma_linhas` fixes the N of the shape warning (an integer above 0).
#[derive(Deserialize)]
#[serde(default)]
pub struct Pr {
    #[serde(rename = "warn_lines")]
    pub aviso_linhas: u64,
    #[serde(rename = "shape_lines")]
    pub forma_linhas: Option<std::num::NonZeroU64>,
    /// Item 115: `"warn"` (the default) or `"off"`; any other value or type
    /// is refused by serde, as an invalid `shape_lines` is.
    pub new_dependencies: NewDependencies,
    /// Item 115: a new dependency first published fewer days ago than this is young.
    pub new_dependency_days: DependencyDays,
}

impl Default for Pr {
    fn default() -> Self {
        Pr {
            aviso_linhas: 500,
            forma_linhas: None,
            new_dependencies: NewDependencies::Warn,
            new_dependency_days: DependencyDays::default(),
        }
    }
}

/// Item 115: `[pr] new_dependencies`.
#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
#[serde(rename_all = "lowercase")]
pub enum NewDependencies {
    #[default]
    Warn,
    Off,
}

/// Item 115: `[pr] new_dependency_days`, an integer from 1 to 36500 (default 30).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct DependencyDays(pub u64);

impl Default for DependencyDays {
    fn default() -> Self {
        DependencyDays(30)
    }
}

impl<'de> Deserialize<'de> for DependencyDays {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        let days = u64::deserialize(d)?;
        if !(1..=36500).contains(&days) {
            return Err(serde::de::Error::custom(format!("new_dependency_days must be from 1 to 36500, not {days}")));
        }
        Ok(DependencyDays(days))
    }
}
