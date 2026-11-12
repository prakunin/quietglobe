import Testing
@testable import QuietGlobeCore

private let globe = KeyStateMachine.globeKeyCode
private let esc = Int64(WordBuffer.Code.escape)
private let ghbdtn: [Int64] = [5, 4, 11, 2, 17, 45]
private let vbh: [Int64] = [9, 11, 4]
private let space: Int64 = 49

private func keys(_ codes: [Int64]) -> [WordBuffer.Key] {
    codes.map { WordBuffer.Key(keyCode: UInt16($0), shift: false, option: false) }
}

private extension KeyStateMachine {
    mutating func typeKeys(_ codes: [Int64], keyboardType: Int64 = 0) {
        for c in codes {
            let out = keyDown(keyCode: c, keyboardType: keyboardType)
            #expect(out == .pass)
        }
    }

    mutating func fnDown() { _ = flagsChanged(fn: true) }
    mutating func fnUp() { _ = flagsChanged(fn: false) }

    mutating func fnEsc(
        autorepeat: Bool = false,
        retypeEnabled: Bool = true,
        secure: Bool = false
    ) -> Output {
        keyDown(keyCode: esc, isAutorepeat: autorepeat,
                retypeEnabled: { retypeEnabled }, secureInputEnabled: { secure })
    }
}

@Suite struct KeyStateMachineTests {
    // MARK: Globe

    @Test func globeDisabledPassesDownAndUpWithoutAction() {
        var m = KeyStateMachine()
        #expect(m.keyDown(keyCode: globe, globeEnabled: { false }) == .pass)
        #expect(m.keyUp(keyCode: globe, globeEnabled: { false }) == .pass)
    }

    @Test func fnEscStillRetypesWithGlobeDisabled() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        let out = m.keyDown(keyCode: esc, globeEnabled: { false })
        #expect(out.consume)
        #expect(out.action != nil)
    }

    @Test func reEnablingGlobeRestoresSwitching() {
        var m = KeyStateMachine()
        #expect(m.keyDown(keyCode: globe, globeEnabled: { false }) == .pass)
        #expect(m.keyUp(keyCode: globe, globeEnabled: { false }) == .pass)
        #expect(m.keyDown(keyCode: globe, globeEnabled: { true }) == .consumed)
        #expect(m.keyUp(keyCode: globe, globeEnabled: { true }) == .init(consume: true, action: .switchLayout))
    }

    @Test func globeKeyDownAndUpAreAlwaysConsumed() {
        var m = KeyStateMachine()
        #expect(m.keyDown(keyCode: globe) == .consumed)
        #expect(m.keyUp(keyCode: globe).consume)
    }

    @Test func cleanGlobeTapSwitchesLayoutOnKeyUp() {
        var m = KeyStateMachine()
        #expect(m.keyDown(keyCode: globe) == .consumed)
        #expect(m.keyUp(keyCode: globe) == .init(consume: true, action: .switchLayout))
    }

    @Test func globeTapWithFnFlagAndNoOtherKeysSwitches() {
        var m = KeyStateMachine()
        m.fnDown()
        #expect(m.keyDown(keyCode: globe) == .consumed)
        m.fnUp()
        #expect(m.keyUp(keyCode: globe).action == .switchLayout)
    }

    @Test func noSwitchIfAnotherKeyWasPressedWhileFnHeld() {
        var m = KeyStateMachine()
        m.fnDown()
        _ = m.keyDown(keyCode: 0)  // Fn+A
        m.fnUp()
        #expect(m.keyUp(keyCode: globe) == .consumed)
        // The modifier flag is consumed by that key-up: the next clean tap switches again.
        #expect(m.keyUp(keyCode: globe).action == .switchLayout)
    }

    @Test func modifierFlagIsNotResetByGlobeKeyDown() {
        // Built-in keyboards: Fn+Esc, and the 179 key-down arrives only at release.
        var m = KeyStateMachine()
        m.fnDown()
        _ = m.fnEsc()
        _ = m.keyUp(keyCode: esc)
        #expect(m.keyDown(keyCode: globe) == .consumed)
        m.fnUp()
        #expect(m.keyUp(keyCode: globe) == .consumed, "Fn+Esc must not switch the layout on Globe release")
    }

    @Test func newFnPressStartsClean() {
        var m = KeyStateMachine()
        m.fnDown()
        _ = m.keyDown(keyCode: 0)
        m.fnUp()
        m.fnDown()  // rising edge clears globeUsedAsModifier
        m.fnUp()
        #expect(m.keyUp(keyCode: globe).action == .switchLayout)
    }

    @Test func repeatedFnDownFlagDoesNotRestartSeries() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn + [space] + vbh)
        m.fnDown()
        _ = m.fnEsc()
        m.fnDown()  // flagsChanged with Fn still set (other modifier changed)
        let out = m.fnEsc()
        guard case let .retype(k, _, sw, _)? = out.action else { Issue.record("no retype"); return }
        #expect(k.count == ghbdtn.count + 1 + vbh.count)
        #expect(!sw)
    }

    // MARK: Fn+Esc

    @Test func fnEscRetypesLastWordAndSwitchesLayout() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn, keyboardType: 40)
        m.fnDown()
        let out = m.fnEsc()
        #expect(out == .init(
            consume: true,
            action: .retype(keys: keys(ghbdtn), deleteCount: 6, switchLayout: true, keyboardType: 40)))
    }

    @Test func fnEscRetypesOnlyTheLastWord() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn + [space] + vbh)
        m.fnDown()
        #expect(m.fnEsc().action == .retype(keys: keys(vbh), deleteCount: 3, switchLayout: true, keyboardType: 0))
    }

    @Test func trailingSpacesBelongToTheRetypedSuffix() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn + [space])
        m.fnDown()
        #expect(m.fnEsc().action ==
            .retype(keys: keys(ghbdtn + [space]), deleteCount: 7, switchLayout: true, keyboardType: 0))
    }

    @Test func furtherEscWhileFnHeldConvertsMoreWords() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn + [space] + vbh)
        m.fnDown()
        _ = m.fnEsc()
        _ = m.keyUp(keyCode: esc)
        let all = ghbdtn + [space] + vbh
        let second = m.fnEsc()
        #expect(second.consume)
        #expect(second.action == .retype(keys: keys(all), deleteCount: 10, switchLayout: false, keyboardType: 0))
    }

    @Test func seriesStopsWhenThereAreNoMoreWords() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        _ = m.fnEsc()
        let second = m.fnEsc()
        #expect(second == .consumed)  // consumed, nothing to convert
    }

    @Test func fnReleaseEndsTheSeries() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn + [space] + vbh)
        m.fnDown()
        _ = m.fnEsc()
        m.fnUp()
        m.fnDown()
        guard case let .retype(k, _, sw, _)? = m.fnEsc().action else { Issue.record("no retype"); return }
        #expect(k == keys(vbh))
        #expect(sw)
    }

    @Test func escKeyUpAfterConsumedFnEscIsSwallowedOnce() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        _ = m.fnEsc()
        #expect(m.keyUp(keyCode: esc) == .consumed)
        #expect(m.keyUp(keyCode: esc) == .pass)
    }

    @Test func escKeyUpWithoutFnEscPasses() {
        var m = KeyStateMachine()
        #expect(m.keyDown(keyCode: esc) == .pass)
        #expect(m.keyUp(keyCode: esc) == .pass)
    }

    @Test func autorepeatEscIsConsumedWithoutNewRetype() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn + [space] + vbh)
        m.fnDown()
        _ = m.fnEsc()
        #expect(m.fnEsc(autorepeat: true) == .consumed)
        #expect(m.fnEsc(autorepeat: true) == .consumed)
        // series was not advanced by the repeats: next real press converts exactly 2 words
        guard case let .retype(k, _, _, _)? = m.fnEsc().action else { Issue.record("no retype"); return }
        #expect(k.count == 10)
    }

    @Test func autorepeatEscDoesNotConsultSecureInput() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        var asked = false
        let out = m.keyDown(keyCode: esc, isAutorepeat: true, secureInputEnabled: { asked = true; return false })
        #expect(out == .consumed)
        #expect(!asked)
    }

    @Test func fnOtherKeyResetsBufferAndPasses() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        #expect(m.keyDown(keyCode: 123) == .pass)  // Fn+Left (Home)
        #expect(m.buffer.isEmpty)
        #expect(m.fnEsc() == .init(consume: true, action: .nothingToRetype))  // nothing to retype
    }

    @Test func fnEscWithRetypeDisabledResetsBufferAndPasses() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        #expect(m.fnEsc(retypeEnabled: false) == .pass)
        #expect(m.buffer.isEmpty)
        // No Esc swallowing was armed.
        #expect(m.keyUp(keyCode: esc) == .pass)
    }

    @Test func retypeEnabledIsOnlyAskedOnFnEsc() {
        var m = KeyStateMachine()
        var asked = 0
        _ = m.keyDown(keyCode: 0, retypeEnabled: { asked += 1; return true })
        _ = m.keyDown(keyCode: esc, retypeEnabled: { asked += 1; return true })  // Esc without Fn
        m.fnDown()
        _ = m.keyDown(keyCode: 0, retypeEnabled: { asked += 1; return true })   // Fn+other
        #expect(asked == 0)
        _ = m.keyDown(keyCode: esc, retypeEnabled: { asked += 1; return true })
        #expect(asked == 1)
    }

    @Test func secureInputBlocksRetypeButStillConsumesEsc() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        #expect(m.fnEsc(secure: true) == .init(consume: true, action: .nothingToRetype))
        #expect(m.keyUp(keyCode: esc) == .consumed)
        // Buffer is kept and the series did not advance.
        #expect(m.fnEsc().action == .retype(keys: keys(ghbdtn), deleteCount: 6, switchLayout: true, keyboardType: 0))
    }

    @Test func fnEscWithEmptyBufferIsNothingToRetype() {
        var m = KeyStateMachine()
        m.fnDown()
        #expect(m.fnEsc() == .init(consume: true, action: .nothingToRetype))
    }

    @Test func fnEscPastAvailableWordsIsNothingToRetype() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        guard case .retype? = m.fnEsc().action else { Issue.record("no retype"); return }
        #expect(m.keyUp(keyCode: esc) == .consumed)
        #expect(m.fnEsc() == .init(consume: true, action: .nothingToRetype))
    }

    @Test func autorepeatFnEscOnEmptyBufferHasNoAction() {
        var m = KeyStateMachine()
        m.fnDown()
        #expect(m.fnEsc(autorepeat: true) == .consumed)
    }

    @Test func fnEscWithRetypeDisabledHasNoBeep() {
        var m = KeyStateMachine()
        m.fnDown()
        #expect(m.fnEsc(retypeEnabled: false) == .pass)
    }

    @Test func escWithoutFnResetsBufferAndPasses() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        #expect(m.keyDown(keyCode: esc) == .pass)
        #expect(m.buffer.isEmpty)
    }

    // MARK: Buffer feeding / resets

    @Test func keyDownsPassAndFeedTheBuffer() {
        var m = KeyStateMachine()
        _ = m.keyDown(keyCode: 0, shift: true)
        _ = m.keyDown(keyCode: 1, option: true)
        #expect(m.buffer.entries == [
            .init(keyCode: 0, shift: true, option: false),
            .init(keyCode: 1, shift: false, option: true)
        ])
    }

    @Test func commandOrControlKeyResetsTheBuffer() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        #expect(m.keyDown(keyCode: 8, command: true) == .pass)
        #expect(m.buffer.isEmpty)
    }

    @Test func keyboardTypeIsRememberedOnlyWhenPositive() {
        var m = KeyStateMachine()
        m.typeKeys([5], keyboardType: 40)
        m.typeKeys([4], keyboardType: 0)
        m.fnDown()
        guard case let .retype(_, _, _, kt)? = m.fnEsc().action else { Issue.record("no retype"); return }
        #expect(kt == 40)
    }

    @Test func keyboardTypeIsNotUpdatedWhileFnHeld() {
        var m = KeyStateMachine()
        m.typeKeys([5], keyboardType: 40)
        m.fnDown()
        _ = m.keyDown(keyCode: 0, keyboardType: 99)
        m.typeKeys([5, 4], keyboardType: 0)
        m.fnUp()
        m.typeKeys([5], keyboardType: 0)
        m.fnDown()
        guard case let .retype(_, _, _, kt)? = m.fnEsc().action else { Issue.record("no retype"); return }
        #expect(kt == 40)
    }

    @Test func mouseDownResetsTheBufferAndPasses() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        #expect(m.mouseDown() == .pass)
        #expect(m.buffer.isEmpty)
    }

    @Test func appActivationResetsTheBuffer() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.appActivated()
        #expect(m.buffer.isEmpty)
    }

    @Test func resetClearsAllState() {
        var m = KeyStateMachine()
        m.typeKeys(ghbdtn)
        m.fnDown()
        _ = m.fnEsc()
        m.reset()
        #expect(m.buffer.isEmpty)
        #expect(m.keyUp(keyCode: esc) == .pass)
        #expect(m.keyUp(keyCode: globe).action == .switchLayout)
    }

    @Test func nonFnKeyUpsPass() {
        var m = KeyStateMachine()
        #expect(m.keyUp(keyCode: 0) == .pass)
        m.fnDown()
        #expect(m.keyUp(keyCode: 0) == .pass)
    }

    @Test func flagsChangedAlwaysPasses() {
        var m = KeyStateMachine()
        #expect(m.flagsChanged(fn: true) == .pass)
        #expect(m.flagsChanged(fn: false) == .pass)
        #expect(m.flagsChanged(fn: false) == .pass)
    }

    // MARK: Scenario

    @Test func fullScenario() {
        var m = KeyStateMachine()
        let all = vbh + [space] + ghbdtn
        m.typeKeys(all, keyboardType: 40)

        m.fnDown()
        let first = m.fnEsc()
        #expect(first == .init(
            consume: true,
            action: .retype(keys: keys(ghbdtn), deleteCount: 6, switchLayout: true, keyboardType: 40)))
        #expect(m.keyUp(keyCode: esc) == .consumed)

        let second = m.fnEsc()
        #expect(second == .init(
            consume: true,
            action: .retype(keys: keys(all), deleteCount: 10, switchLayout: false, keyboardType: 40)))
        #expect(m.keyUp(keyCode: esc) == .consumed)

        m.fnUp()
        // Globe key-up after the series: consumed, no layout switch.
        #expect(m.keyUp(keyCode: globe) == .consumed)
    }
}
