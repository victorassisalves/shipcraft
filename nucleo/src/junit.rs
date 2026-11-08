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

    /// Every case of the report, whatever its outcome, sorted.
    pub fn ids(&self) -> Vec<String> {
        self.cases.keys().cloned().collect()
    }

    /// Item 55: the report with only the cases `keep` holds.
    pub fn only(mut self, keep: &BTreeSet<String>) -> Report {
        self.cases.retain(|id, _| keep.contains(id));
        self.groups.retain(|id| keep.contains(id));
        self
    }

    pub fn is_green(&self) -> bool {
        self.cases.values().all(|o| matches!(o, Outcome::Passed | Outcome::Skipped))
    }

    /// Item 97: the cases that keep the report from being green (failures
    /// and errors), each once, in byte order of the full id.
    pub fn not_green(&self) -> Vec<String> {
        self.cases
            .iter()
            .filter(|(_, o)| !matches!(o, Outcome::Passed | Outcome::Skipped))
            .map(|(id, _)| id.clone())
            .collect()
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

#[cfg(test)]
mod tests {
    use super::Report;

    fn report(cases: &str) -> Report {
        Report::parse(&format!("<testsuite>{cases}</testsuite>")).unwrap()
    }

    #[test]
    fn not_green_holds_failures_and_errors_only() {
        let r = report(
            r#"<testcase classname="t" name="fail"><failure/></testcase>
               <testcase classname="t" name="err"><error/></testcase>
               <testcase classname="t" name="skip"><skipped/></testcase>
               <testcase classname="t" name="pass"/>"#,
        );
        assert_eq!(r.not_green(), ["t::err", "t::fail"]);
    }

    #[test]
    fn a_repeated_id_counts_once_with_its_worst_outcome() {
        let r = report(
            r#"<testcase classname="t" name="retry"><failure/></testcase>
               <testcase classname="t" name="retry"/>
               <testcase classname="t" name="late"/>
               <testcase classname="t" name="late"><error/></testcase>
               <testcase classname="t" name="ok"/>
               <testcase classname="t" name="ok"/>"#,
        );
        assert_eq!(r.not_green(), ["t::late", "t::retry"]);
    }

    #[test]
    fn ids_carry_the_suite_prefix_and_sort_in_byte_order_across_suites() {
        let mut all = Report::empty();
        all.absorb("web", report(r#"<testcase classname="a" name="x"><failure/></testcase>"#));
        all.absorb(
            "",
            report(
                r#"<testcase classname="tests.test_value" name="test_value"><failure/></testcase>
                   <testcase classname="Zeta" name="up"><error/></testcase>"#,
            ),
        );
        all.absorb(
            "api",
            report(
                r#"<testcase classname="tests.test_value" name="test_value"><error/></testcase>
                   <testcase classname="tests.test_value" name="fine"/>"#,
            ),
        );
        assert_eq!(
            all.not_green(),
            ["Zeta::up", "api:tests.test_value::test_value", "tests.test_value::test_value", "web:a::x"]
        );
    }

    #[test]
    fn a_group_failure_counts_once_under_its_id() {
        let r = report(
            r#"<testcase classname="src/a.test.ts" name="block"><failure/></testcase>
               <testcase classname="src/a.test.ts" name="block &gt; one"><skipped/></testcase>
               <testcase classname="src/a.test.ts" name="block &gt; two"><skipped/></testcase>"#,
        );
        assert_eq!(r.group_failures(), ["src/a.test.ts::block"]);
        assert_eq!(r.not_green(), ["src/a.test.ts::block"]);
    }
}
