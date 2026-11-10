import pytest

from vio_backend.catalogue_harvest import extract_snapshot, validate_public_url


def test_extract_snapshot_collects_course_code_candidates():
    snapshot = extract_snapshot(
        "https://funaab.edu.ng/mts-course-synopsis/",
        "<html><title>MTS Course Synopsis</title><body><h2>100 Level</h2><p>MTS 101 Algebra</p></body></html>",
        "2026-11-09T00:00:00+00:00",
    )
    assert snapshot["page_title"] == "MTS Course Synopsis"
    assert snapshot["course_code_candidates"] == ["MTS101"]


@pytest.mark.parametrize("url", ["http://funaab.edu.ng/", "https://example.com/", "https://portal.funaab.edu.ng/login"])
def test_rejects_nonpublic_or_unapproved_urls(url):
    with pytest.raises(ValueError):
        validate_public_url(url)


def test_accepts_public_admissions_page():
    validate_public_url("https://admission.funaab.edu.ng/2026/programmes.php")
