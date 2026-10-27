//! `josh.toml` workspace config. `:workspace=` uses it in place of `workspace.josh`.
//!
//! ```toml
//! exclude = ["**/BUCK"]
//!
//! [map]
//! "vendor/clickhouse-c" = "vendor/clickhouse-c"
//! ```
//!
//! The first commit with a `josh.toml` applies its config to all earlier history.

use super::*;
use std::collections::BTreeMap;
use std::path::{Component, PathBuf};

pub(crate) const FILE_NAME: &str = "josh.toml";

#[derive(Debug, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorkspaceConfig {
    /// View path = repository path.
    #[serde(default)]
    map: BTreeMap<String, String>,
    /// Glob patterns to drop from the view.
    #[serde(default)]
    exclude: Vec<String>,
}

pub(crate) fn read(
    transaction: &cache::Transaction,
    odb: &josh_memodb::Odb,
    reader: &tree::TreeReader,
    path: &Path,
) -> anyhow::Result<Option<WorkspaceConfig>> {
    let file = normalize_path(&path.join(FILE_NAME));
    let Some(entry) = tree::get_path_entry_at(transaction, odb, reader, &file)? else {
        return Ok(None);
    };
    let text = tree::blob_text(odb, entry.oid);
    let config =
        toml::from_str(&text).map_err(|err| anyhow!("invalid {}: {err}", file.display()))?;
    Ok(Some(config))
}

fn relative_path(what: &str, path: &str) -> anyhow::Result<PathBuf> {
    let p = PathBuf::from(path);
    let normal = p.components().all(|c| matches!(c, Component::Normal(_)));
    if path.is_empty() || !normal {
        return Err(anyhow!(
            "{FILE_NAME}: {what} `{path}` must be a relative path without `.` or `..`"
        ));
    }
    Ok(p)
}

impl WorkspaceConfig {
    pub(crate) fn tree_filter(&self, path: &Path) -> anyhow::Result<Filter> {
        let base = Filter::new().subdir(path);
        let mut parts = Vec::with_capacity(self.map.len() + 1);
        for (dst, src) in &self.map {
            let dst = relative_path("map destination", dst)?;
            let src = relative_path("map source", src)?;
            parts.push(Filter::new().subdir(src).prefix(dst));
        }
        parts.push(base);
        let mut view = compose(&parts);

        if !self.exclude.is_empty() {
            let patterns = self
                .exclude
                .iter()
                .map(|p| Filter::new().pattern(p))
                .collect::<anyhow::Result<Vec<_>>>()
                .with_context(|| format!("{FILE_NAME}: invalid exclude pattern"))?;
            view = view.exclude(compose(&patterns));
        }

        Ok(compose(&[base.file(FILE_NAME), view]))
    }
}
