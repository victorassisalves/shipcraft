"""durations.py <junit.xml>...: acceptance/durations.tsv from the JUnit reports of a full CI run.

Prints "<language> <case> <seconds>" for every case that ran (skipped cases are left out), sorted.
To refresh the split after the battery changes:
  gh run download <run id> -p 'junit-*' -D /tmp/junit
  python3 acceptance/tools/durations.py /tmp/junit/*/*.xml > acceptance/durations.tsv
tools/shard.py spreads the shards by these times; a case missing here counts as the median.
"""
import sys
import xml.etree.ElementTree as ET

secs = {}
for path in sys.argv[1:]:
    for tc in ET.parse(path).getroot().iter('testcase'):
        if tc.find('skipped') is not None:
            continue
        lang, case = tc.get('name').split('::', 1)
        secs[(lang, case)] = float(tc.get('time', '0'))
if not secs:
    sys.exit('durations.py: no case ran in these reports')
print('# <language> <case> <seconds>, from acceptance/tools/durations.py')
for (lang, case), s in sorted(secs.items()):
    print('%s %s %.1f' % (lang, case, s))
