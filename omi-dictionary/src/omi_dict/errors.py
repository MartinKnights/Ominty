"""Stable error codes (spec §21).  The CLI/JSON layer returns these; the UI
renders friendly text, never stack traces."""

from __future__ import annotations


class OmDictError(Exception):
    """Base error with a stable ``code`` for machine consumers."""

    code = "OMI_DICT_ERROR"

    def __init__(self, message: str = "", *, code: str | None = None) -> None:
        super().__init__(message)
        if code:
            self.code = code

    def to_dict(self) -> dict:
        return {"error": self.code, "message": str(self)}


class DictionaryUnavailable(OmDictError):
    code = "DICTIONARY_UNAVAILABLE"


class DictionaryNeedsRebuild(OmDictError):
    code = "DICTIONARY_INDEX_REQUIRES_REBUILDING"


class NoEntryFound(OmDictError):
    code = "NO_ENTRY_FOUND"


class SelectionUnavailable(OmDictError):
    code = "UNABLE_TO_OBTAIN_SELECTED_TEXT"


class BadFormat(OmDictError):
    code = "BAD_DICTIONARY_FORMAT"