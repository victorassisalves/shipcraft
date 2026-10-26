//! The JUnit report: what happened to each test case.

use std::collections::BTreeMap;

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
        for case in document.descendants().filter(|n| n.has_tag_name("testcase")) {
            let outcome = outcome_of(case);
            let id = case_id(case.attribute("classname").unwrap_or(""), case.attribute("name").unwrap_or(""));
            let worst = cases.get(&id).map_or(outcome, |seen: &Outcome| outcome.max(*seen));
            cases.insert(id, worst);
        }
        Some(Report { cases })
    }

    pub fn empty() -> Report {
        Report { cases: BTreeMap::new() }
    }

    /// Adds another suite's cases; with a suite name, its cases are
    /// `<name>:<case>`, so the same test name in two suites is two cases.
    pub fn absorb(&mut self, suite: &str, other: Report) {
        for (id, outcome) in other.cases {
            let id = if suite.is_empty() { id } else { format!("{suite}:{id}") };
            let worst = self.cases.get(&id).map_or(outcome, |seen| outcome.max(*seen));
            self.cases.insert(id, worst);
        }
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
