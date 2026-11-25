//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import CallKit
import Testing
import YollaVoiceSDK
@testable import YollaVoiceExample

struct CallStateMappingTests {
    @Test func describesEndReasons() {
        #expect(CallViewModel.describe(.busy, error: nil) == "Busy")
        #expect(CallViewModel.describe(.noAnswer, error: nil) == "No answer")
        #expect(CallViewModel.describe(.rejected, error: nil) == "Rejected")
        #expect(CallViewModel.describe(.remoteHangup, error: nil) == "Call ended by the other side")
        #expect(CallViewModel.describe(.localHangup, error: nil) == "Call ended")
        #expect(CallViewModel.describe(.cancelled, error: nil) == "Cancelled")
        #expect(
            CallViewModel.describe(
                .failed,
                error: VoiceError(code: "insufficient_balance", message: "Payment Required", sipStatus: 402)
            )
                == "Failed: insufficient_balance (Payment Required, SIP 402)"
        )
        #expect(CallViewModel.describe(.failed, error: nil) == "Failed")
    }

    @Test func mapsToCallKitEndedReasons() {
        #expect(CallViewModel.cxEndedReason(.remoteHangup) == .remoteEnded)
        #expect(CallViewModel.cxEndedReason(.noAnswer) == .unanswered)
        #expect(CallViewModel.cxEndedReason(.busy) == .failed)
        #expect(CallViewModel.cxEndedReason(.rejected) == .failed)
        #expect(CallViewModel.cxEndedReason(.failed) == .failed)
        #expect(CallViewModel.cxEndedReason(.localHangup) == nil) // reported through CXEndCallAction
        #expect(CallViewModel.cxEndedReason(.cancelled) == nil)
    }
}
