//! The JUnit report: what happened to each test case.

use std::collections::{BTreeMap, BTreeSet};

/// Ordered from best to worst, so a case reported twice keeps its worst outcome.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Outcome {
    Passed,
    Skipped,
    Failed,
    /// The case did not reach its assertions (collection or setup error).
    Error,
}

pub struct Report {
    cases: BTreeMap<String, Outcome>,
    /// Item 52: failed cases that are a vitest block whose tests were all skipped.
    groups: BTreeSet<String>,
}

impl Report {
    /// None when the text is not a JUnit report.
    pub fn parse(xml: &str) -> Option<Report> {
        let document = roxmltree::Document::parse(xml).ok()?;
        let root = document.root_element().tag_name().name();
        if root != "testsuites" && root != "testsuite" {
            return None;
        }
        let mut cases = BTreeMap::new();
        let mut names = Vec::new();
        for case in document.descendants().filter(|n| n.has_tag_name("testcase")) {
            let outcome = outcome_of(case);
            let (classname, name) = (case.attribute("classname").unwrap_or(""), case.attribute("name").unwrap_or(""));
            let id = case_id(classname, name);
            let worst = cases.get(&id).map_or(outcome, |seen: &Outcome| outcome.max(*seen));
            cases.insert(id, worst);
            names.push((classname, name));
        }
        let groups = group_failures(&cases, &names);
        Some(Report { cases, groups })
    }

    pub fn empty() -> Report {
        Report { cases: BTreeMap::new(), groups: BTreeSet::new() }
    }

    /// Adds another suite's cases; with a suite name, its cases are
    /// `<name>:<case>`, so the same test name in two suites is two cases.
    pub fn absorb(&mut self, suite: &str, other: Report) {
        for (id, outcome) in other.cases {
            let id = if suite.is_empty() { id } else { format!("{suite}:{id}") };
            let worst = self.cases.get(&id).map_or(outcome, |seen| outcome.max(*seen));
            self.cases.insert(id, worst);
        }
        for id in other.groups {
            self.groups.insert(if suite.is_empty() { id } else { format!("{suite}:{id}") });
        }
    }

    /// Item 52: the failed cases that are a group failure, sorted.
    pub fn group_failures(&self) -> Vec<String> {
        self.groups.iter().filter(|id| self.outcome(id) == Some(Outcome::Failed)).cloned().collect()
    }

    pub fn outcome(&self, case: &str) -> Option<Outcome> {
        self.cases.get(case).copied()
    }

    /// The cases with this outcome, sorted.
    pub fn cases_with(&self, outcome: Outcome) -> Vec<String> {
        self.cases.iter().filter(|(_, o)| **o == outcome).map(|(id, _)| id.clone()).collect()
    }

    /// Every case that ran, skipped ones excluded.
    pub fn cases_run(&self) -> Vec<String> {
        self.cases.iter().filter(|(_, o)| **o != Outcome::Skipped).map(|(id, _)| id.clone()).collect()
    }

    pub fn is_green(&self) -> bool {
        self.cases.values().all(|o| matches!(o, Outcome::Passed | Outcome::Skipped))
    }
}

/// Item 52: a failed case `C::N` (C not empty) is a vitest block whose
/// `beforeAll` failed when the same document holds cases `C::N > ...` and
/// every one of them is skipped.
fn group_failures(cases: &BTreeMap<String, Outcome>, names: &[(&str, &str)]) -> BTreeSet<String> {
    let outcome = |classname: &str, name: &str| cases.get(&case_id(classname, name)).copied();
    let mut groups = BTreeSet::new();
    for &(classname, name) in names {
        if classname.is_empty() || outcome(classname, name) != Some(Outcome::Failed) {
            continue;
        }
        let prefix = format!("{name} > ");
        let mut children =
            names.iter().filter(|(c, n)| *c == classname && n.starts_with(&prefix)).map(|(c, n)| outcome(c, n));
        let first = children.next();
        if first.is_some() && first.into_iter().chain(children).all(|o| o == Some(Outcome::Skipped)) {
            groups.insert(case_id(classname, name));
        }
    }
    groups
}

fn outcome_of(case: roxmltree::Node) -> Outcome {
    let has = |tag: &str| case.children().any(|child| child.has_tag_name(tag));
    if has("error") {
        Outcome::Error
    } else if has("failure") {
        Outcome::Failed
    } else if has("skipped") {
        Outcome::Skipped
    } else {
        Outcome::Passed
    }
}

fn case_id(classname: &str, name: &str) -> String {
    if classname.is_empty() {
        name.to_string()
    } else {
        format!("{classname}::{name}")
    }
}
