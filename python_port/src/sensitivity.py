"""Sensitivity matrix loading and ID mapping for localization."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np


EXPECTED_SENSORS = 33
EXPECTED_JUNCTIONS = 782


@dataclass(frozen=True)
class SensitivityData:
    s: np.ndarray
    s_norm: np.ndarray
    junction_ids: tuple[str, ...]
    sensor_indices: np.ndarray
    junction_to_col: dict[str, int]

    @property
    def sensor_count(self) -> int:
        return int(self.s.shape[0])

    @property
    def junction_count(self) -> int:
        return int(self.s.shape[1])


def load_sensitivity_matrix(path: Path) -> SensitivityData:
    """Load `sensitivity_matrix.mat`, normalizing MATLAB/HDF5 orientation."""
    if not path.exists():
        raise FileNotFoundError(f"Sensitivity matrix not found: {path}")
    try:
        from scipy.io import loadmat

        raw = loadmat(path, squeeze_me=False, struct_as_record=False)
        data = {key: value for key, value in raw.items() if not key.startswith("__")}
        return _from_loaded_mat(data, hdf5_orientation=False)
    except NotImplementedError:
        return _load_hdf5_sensitivity(path)
    except ValueError as exc:
        if "Unknown mat file type" in str(exc):
            return _load_hdf5_sensitivity(path)
        raise


def _load_hdf5_sensitivity(path: Path) -> SensitivityData:
    import h5py

    with h5py.File(path, "r") as h5:
        required = {"S", "S_norm", "junction_ids", "sensor_indices"}
        missing = required.difference(h5.keys())
        if missing:
            raise ValueError(f"Sensitivity MAT missing fields: {sorted(missing)}")

        junction_ids = tuple(_read_matlab_string_refs(h5, h5["junction_ids"]))
        data = {
            "S": np.asarray(h5["S"][()], dtype=float),
            "S_norm": np.asarray(h5["S_norm"][()], dtype=float),
            "junction_ids": junction_ids,
            "sensor_indices": np.asarray(h5["sensor_indices"][()]).reshape(-1),
        }
    return _from_loaded_mat(data, hdf5_orientation=True)


def _from_loaded_mat(data: dict[str, object], hdf5_orientation: bool) -> SensitivityData:
    missing = {"S", "S_norm", "junction_ids", "sensor_indices"}.difference(data)
    if missing:
        raise ValueError(f"Sensitivity MAT missing fields: {sorted(missing)}")

    junction_ids = _coerce_junction_ids(data["junction_ids"])
    s = np.asarray(data["S"], dtype=float)
    s_norm = np.asarray(data["S_norm"], dtype=float)
    if hdf5_orientation or _looks_transposed(s, len(junction_ids)):
        s = s.T
    if hdf5_orientation or _looks_transposed(s_norm, len(junction_ids)):
        s_norm = s_norm.T

    sensor_indices = np.asarray(data["sensor_indices"]).reshape(-1)
    if np.all(np.isfinite(sensor_indices.astype(float))) and np.allclose(
        sensor_indices.astype(float), np.rint(sensor_indices.astype(float))
    ):
        sensor_indices = sensor_indices.astype(int)
    _validate_shapes(s, s_norm, junction_ids)
    junction_to_col = {junction_id: idx for idx, junction_id in enumerate(junction_ids)}
    if len(junction_to_col) != len(junction_ids):
        raise ValueError("Sensitivity junction_ids contain duplicates.")

    return SensitivityData(
        s=s,
        s_norm=s_norm,
        junction_ids=tuple(junction_ids),
        sensor_indices=sensor_indices,
        junction_to_col=junction_to_col,
    )


def _looks_transposed(arr: np.ndarray, junction_count: int) -> bool:
    return arr.ndim == 2 and arr.shape[0] == junction_count and arr.shape[1] == EXPECTED_SENSORS


def _validate_shapes(s: np.ndarray, s_norm: np.ndarray, junction_ids: list[str]) -> None:
    expected = (EXPECTED_SENSORS, EXPECTED_JUNCTIONS)
    if s.shape != expected:
        raise ValueError(f"S must have shape {expected}, got {s.shape}")
    if s_norm.shape != expected:
        raise ValueError(f"S_norm must have shape {expected}, got {s_norm.shape}")
    if len(junction_ids) != EXPECTED_JUNCTIONS:
        raise ValueError(f"Expected {EXPECTED_JUNCTIONS} junction IDs, got {len(junction_ids)}")


def _coerce_junction_ids(value: object) -> list[str]:
    if isinstance(value, tuple):
        return [str(item) for item in value]
    arr = np.asarray(value, dtype=object).reshape(-1)
    out: list[str] = []
    for item in arr:
        if isinstance(item, str):
            out.append(item)
        elif isinstance(item, bytes):
            out.append(item.decode("utf-8"))
        elif isinstance(item, np.ndarray):
            out.append(_chars_to_string(item))
        else:
            nested = np.asarray(item, dtype=object).reshape(-1)
            out.append(str(nested[0]) if len(nested) else str(item))
    return out


def _read_matlab_string_refs(h5: object, dataset: object) -> list[str]:
    values = []
    refs = np.asarray(dataset[()]).reshape(-1)
    for ref in refs:
        values.append(_chars_to_string(h5[ref][()]))
    return values


def _chars_to_string(value: object) -> str:
    arr = np.asarray(value).reshape(-1)
    if arr.dtype.kind in {"u", "i"}:
        return "".join(chr(int(ch)) for ch in arr if int(ch) != 0)
    return "".join(str(ch) for ch in arr)
