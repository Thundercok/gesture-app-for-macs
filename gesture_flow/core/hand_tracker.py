"""
Hand Tracker - High Performance Apple Vision Hand Pose Engine with 21 Landmarks
Runs directly on Apple Neural Engine (ANE) at 60-70+ FPS with ultra-low CPU.
"""

import math
from typing import NamedTuple, List, Optional, Tuple, Dict
import cv2
import numpy as np
import Vision
import Quartz


class HandPose(NamedTuple):
    landmarks: List[Tuple[float, float, float]]  # Normalized (x, y, z) 0.0 - 1.0 (Vision origin: bottom-left)
    pixel_landmarks: List[Tuple[int, int]]       # Image coordinates (x_px, y_px) (OpenCV origin: top-left)
    extended_fingers: Dict[str, bool]           # {"thumb": bool, "index": bool, ...}
    finger_count: int                           # 0 - 5
    pinch_distance: float                       # Thumb-tip to index-tip distance
    index_middle_distance: float                # Index-tip to middle-tip distance
    palm_center: Tuple[float, float]            # (x, y) in OpenCV pixel coordinates
    hand_size: float                            # Normalization scale factor


# Apple Vision Joint Topology in Order (21 joints)
JOINTS = [
    Vision.VNHumanHandPoseObservationJointNameWrist,      # 0
    Vision.VNHumanHandPoseObservationJointNameThumbCMC,   # 1
    Vision.VNHumanHandPoseObservationJointNameThumbMP,    # 2
    Vision.VNHumanHandPoseObservationJointNameThumbIP,    # 3
    Vision.VNHumanHandPoseObservationJointNameThumbTip,   # 4
    Vision.VNHumanHandPoseObservationJointNameIndexMCP,   # 5
    Vision.VNHumanHandPoseObservationJointNameIndexPIP,   # 6
    Vision.VNHumanHandPoseObservationJointNameIndexDIP,   # 7
    Vision.VNHumanHandPoseObservationJointNameIndexTip,   # 8
    Vision.VNHumanHandPoseObservationJointNameMiddleMCP,  # 9
    Vision.VNHumanHandPoseObservationJointNameMiddlePIP,  # 10
    Vision.VNHumanHandPoseObservationJointNameMiddleDIP,  # 11
    Vision.VNHumanHandPoseObservationJointNameMiddleTip,  # 12
    Vision.VNHumanHandPoseObservationJointNameRingMCP,    # 13
    Vision.VNHumanHandPoseObservationJointNameRingPIP,    # 14
    Vision.VNHumanHandPoseObservationJointNameRingDIP,    # 15
    Vision.VNHumanHandPoseObservationJointNameRingTip,    # 16
    Vision.VNHumanHandPoseObservationJointNameLittleMCP,  # 17
    Vision.VNHumanHandPoseObservationJointNameLittlePIP,  # 18
    Vision.VNHumanHandPoseObservationJointNameLittleDIP,  # 19
    Vision.VNHumanHandPoseObservationJointNameLittleTip,  # 20
]

HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),        # Thumb
    (0, 5), (5, 6), (6, 7), (7, 8),        # Index
    (0, 9), (9, 10), (10, 11), (11, 12),   # Middle
    (0, 13), (13, 14), (14, 15), (15, 16), # Ring
    (0, 17), (17, 18), (18, 19), (19, 20), # Pinky
    (5, 9), (9, 13), (13, 17)              # Palm base
]


class HandTracker:
    """Detects and parses 21 hand landmarks in real-time via Apple Vision."""

    def __init__(self, min_detection_confidence: float = 0.5, **kwargs):
        self.min_confidence = min_detection_confidence
        self.colorspace = Quartz.CGColorSpaceCreateDeviceRGB()
        self.request = Vision.VNDetectHumanHandPoseRequest.alloc().init()
        self.request.setMaximumHandCount_(1)

    def process(self, frame: np.ndarray) -> Optional[HandPose]:
        """Processes an OpenCV BGR frame and returns a HandPose namedtuple."""
        h, w, _ = frame.shape

        # Convert OpenCV frame (BGR) to RGB bytes for Quartz CGImage
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        raw_bytes = frame_rgb.tobytes()

        provider = Quartz.CGDataProviderCreateWithData(None, raw_bytes, len(raw_bytes), None)
        cg_img = Quartz.CGImageCreate(
            w, h, 8, 24, w * 3, self.colorspace,
            Quartz.kCGBitmapByteOrderDefault, provider, None, False,
            Quartz.kCGRenderingIntentDefault
        )

        handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg_img, None)
        success, error = handler.performRequests_error_([self.request], None)

        if not success or not self.request.results():
            return None

        obs = self.request.results()[0]

        # Extract all 21 points
        points_map = {}
        for joint in JOINTS:
            point, err = obs.recognizedPointForJointName_error_(joint, None)
            if point is not None and point.confidence() > self.min_confidence:
                # Vision coordinates: (0,0) is bottom-left
                vx = float(point.location().x)
                vy = float(point.location().y)
                # Convert to image pixel coordinates (0,0 is top-left)
                px = int(vx * w)
                py = int((1.0 - vy) * h)
                points_map[joint] = (vx, vy, px, py)

        # Ensure critical points exist
        wrist_key = JOINTS[0]
        idx_tip_key = JOINTS[8]
        if wrist_key not in points_map or idx_tip_key not in points_map:
            return None

        landmarks = []
        pixel_landmarks = []
        for joint in JOINTS:
            if joint in points_map:
                vx, vy, px, py = points_map[joint]
                landmarks.append((vx, 1.0 - vy, 0.0))  # Standardized top-left normalized
                pixel_landmarks.append((px, py))
            else:
                landmarks.append((0.0, 0.0, 0.0))
                pixel_landmarks.append((0, 0))

        # Check Finger Extensions (Tip higher than PIP joint in Vision space -> vy_tip > vy_pip)
        def is_ext(tip_idx, pip_idx):
            tip_j = JOINTS[tip_idx]
            pip_j = JOINTS[pip_idx]
            if tip_j in points_map and pip_j in points_map:
                return points_map[tip_j][1] > points_map[pip_j][1]
            return False

        index_ext = is_ext(8, 6)
        middle_ext = is_ext(12, 10)
        ring_ext = is_ext(16, 14)
        pinky_ext = is_ext(20, 18)

        # Thumb extension
        thumb_ext = False
        t_tip_j = JOINTS[4]
        t_mcp_j = JOINTS[2]
        p_mcp_j = JOINTS[17]
        if t_tip_j in points_map and t_mcp_j in points_map and p_mcp_j in points_map:
            d_tip = math.hypot(points_map[t_tip_j][0] - points_map[p_mcp_j][0], points_map[t_tip_j][1] - points_map[p_mcp_j][1])
            d_mcp = math.hypot(points_map[t_mcp_j][0] - points_map[p_mcp_j][0], points_map[t_mcp_j][1] - points_map[p_mcp_j][1])
            thumb_ext = d_tip > d_mcp * 1.15

        extended_fingers = {
            "thumb": thumb_ext,
            "index": index_ext,
            "middle": middle_ext,
            "ring": ring_ext,
            "pinky": pinky_ext
        }
        finger_count = sum(1 for ext in extended_fingers.values() if ext)

        # Scale / Hand size
        w_pt = points_map[wrist_key]
        m_mcp_j = JOINTS[9]
        if m_mcp_j in points_map:
            m_pt = points_map[m_mcp_j]
            hand_size = max(0.05, math.hypot(m_pt[0] - w_pt[0], m_pt[1] - w_pt[1]))
        else:
            hand_size = 0.2

        # Pinch distance (Thumb Tip to Index Tip)
        if t_tip_j in points_map:
            i_pt = points_map[idx_tip_key]
            t_pt = points_map[t_tip_j]
            raw_pinch = math.hypot(t_pt[0] - i_pt[0], t_pt[1] - i_pt[1])
            pinch_dist = raw_pinch / hand_size
        else:
            pinch_dist = 1.0

        # Index to Middle distance
        m_tip_j = JOINTS[12]
        if m_tip_j in points_map:
            i_pt = points_map[idx_tip_key]
            m_pt = points_map[m_tip_j]
            raw_im = math.hypot(m_pt[0] - i_pt[0], m_pt[1] - i_pt[1])
            im_dist = raw_im / hand_size
        else:
            im_dist = 1.0

        # Palm Center
        palm_x = w_pt[2]
        palm_y = w_pt[3]

        return HandPose(
            landmarks=landmarks,
            pixel_landmarks=pixel_landmarks,
            extended_fingers=extended_fingers,
            finger_count=finger_count,
            pinch_distance=pinch_dist,
            index_middle_distance=im_dist,
            palm_center=(palm_x, palm_y),
            hand_size=hand_size
        )

    def draw_landmarks(self, frame: np.ndarray, pixel_landmarks: List[Tuple[int, int]]):
        """Draws aesthetic hand skeleton landmarks on frame."""
        for p1_idx, p2_idx in HAND_CONNECTIONS:
            if p1_idx < len(pixel_landmarks) and p2_idx < len(pixel_landmarks):
                pt1 = pixel_landmarks[p1_idx]
                pt2 = pixel_landmarks[p2_idx]
                if pt1 != (0, 0) and pt2 != (0, 0):
                    cv2.line(frame, pt1, pt2, (0, 255, 128), 2, cv2.LINE_AA)

        for i, (px, py) in enumerate(pixel_landmarks):
            if (px, py) != (0, 0):
                color = (0, 200, 255) if i in [4, 8, 12, 16, 20] else (255, 255, 255)
                radius = 5 if i in [4, 8, 12, 16, 20] else 3
                cv2.circle(frame, (px, py), radius, color, -1, cv2.LINE_AA)
