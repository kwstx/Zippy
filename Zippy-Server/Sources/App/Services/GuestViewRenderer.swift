import Vapor
import Foundation

/// Renders a lightweight, zero-dependency HTML page for guest viewing and payment.
/// Mirrors the minimalist Uber aesthetic: stark black and white, zero logos, crisp typography.
enum GuestViewRenderer {

    /// Renders the complete HTML document for a split session.
    static func render(session: SplitSession, receipt: ExtractedReceipt, token: String, baseURL: String) -> String {
        let balances = session.balances
        let receiptTotal = receipt.total
        let totalCollected = balances.filter(\.isPaid).reduce(0.0) { $0 + $1.total }
        let paidCount = balances.filter(\.isPaid).count
        let totalCount = balances.count
        let progressPercent = totalCount > 0 ? Int((Double(paidCount) / Double(totalCount)) * 100) : 0
        let isAllPaid = totalCount > 0 && paidCount == totalCount

        // Pre-compute JSON for client-side JavaScript
        let sessionDataJSON: String
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(balances)
            sessionDataJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            sessionDataJSON = "[]"
        }

        // Build item assignments lookup for individual item breakdowns
        let assignments = session.assignments

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <meta name="theme-color" content="#000000">
            <meta name="apple-mobile-web-app-capable" content="yes">
            <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
            <title>Split Receipt · \(escapeHTML(formatCurrency(receiptTotal)))</title>
            <style>
                *, *::before, *::after {
                    box-sizing: border-box;
                    margin: 0;
                    padding: 0;
                    -webkit-font-smoothing: antialiased;
                }
                :root {
                    --bg: #FFFFFF;
                    --text: #000000;
                    --text-secondary: #6B6B6B;
                    --text-muted: #8E8E8E;
                    --border: #E5E5E5;
                    --border-dark: #000000;
                    --surface: #FAFAFA;
                    --surface-hover: #F2F2F2;
                    --paid-bg: #000000;
                    --paid-text: #FFFFFF;
                    --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Uber Move Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    --font-mono: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
                }
                body {
                    background-color: var(--bg);
                    color: var(--text);
                    font-family: var(--font-sans);
                    line-height: 1.4;
                    min-height: 100vh;
                    padding: 0;
                }
                .container {
                    max-width: 480px;
                    margin: 0 auto;
                    padding: 24px 20px 60px 20px;
                }
                /* Typography */
                .mono-label {
                    font-family: var(--font-mono);
                    font-size: 11px;
                    font-weight: 600;
                    letter-spacing: 0.08em;
                    text-transform: uppercase;
                    color: var(--text-secondary);
                }
                .price-lg {
                    font-family: var(--font-sans);
                    font-size: 44px;
                    font-weight: 700;
                    letter-spacing: -0.03em;
                    color: var(--text);
                    margin: 4px 0;
                }
                .price-mono {
                    font-family: var(--font-mono);
                    font-variant-numeric: tabular-nums;
                }
                /* Dividers */
                .divider {
                    height: 1px;
                    background-color: var(--border);
                    margin: 20px 0;
                    border: none;
                }
                .divider-thick {
                    height: 2px;
                    background-color: var(--text);
                    margin: 20px 0;
                    border: none;
                }
                /* Header Section */
                .header-section {
                    padding-top: 12px;
                }
                .status-badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    font-family: var(--font-mono);
                    font-size: 11px;
                    font-weight: 600;
                    text-transform: uppercase;
                    letter-spacing: 0.05em;
                    padding: 4px 8px;
                    border: 1px solid var(--border-dark);
                    margin-top: 8px;
                }
                .status-badge.all-paid {
                    background-color: var(--text);
                    color: var(--bg);
                }
                /* Progress bar */
                .progress-bar-container {
                    width: 100%;
                    height: 4px;
                    background-color: var(--border);
                    margin: 16px 0 8px 0;
                    overflow: hidden;
                }
                .progress-bar-fill {
                    height: 100%;
                    background-color: var(--text);
                    width: \(progressPercent)%;
                    transition: width 0.4s ease;
                }
                .progress-text {
                    display: flex;
                    justify-content: space-between;
                    font-family: var(--font-mono);
                    font-size: 11px;
                    color: var(--text-secondary);
                }
                /* Participant Cards */
                .section-title {
                    font-family: var(--font-mono);
                    font-size: 12px;
                    font-weight: 700;
                    letter-spacing: 0.08em;
                    text-transform: uppercase;
                    color: var(--text);
                    margin-bottom: 12px;
                }
                .participant-list {
                    display: flex;
                    flex-direction: column;
                    gap: 8px;
                }
                .participant-card {
                    border: 1px solid var(--border);
                    background-color: var(--bg);
                    padding: 16px;
                    cursor: pointer;
                    transition: border-color 0.15s ease, background-color 0.15s ease;
                    user-select: none;
                }
                .participant-card:hover {
                    background-color: var(--surface);
                }
                .participant-card.selected {
                    border-color: var(--border-dark);
                    border-width: 2px;
                    padding: 15px;
                    background-color: var(--surface);
                }
                .card-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }
                .person-info {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                }
                .person-avatar {
                    width: 32px;
                    height: 32px;
                    background-color: var(--text);
                    color: var(--bg);
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-family: var(--font-mono);
                    font-size: 13px;
                    font-weight: 700;
                }
                .person-name {
                    font-size: 16px;
                    font-weight: 600;
                    color: var(--text);
                }
                .person-amount {
                    text-align: right;
                }
                .person-total {
                    font-size: 18px;
                    font-weight: 700;
                    font-family: var(--font-mono);
                }
                .paid-tag {
                    font-family: var(--font-mono);
                    font-size: 10px;
                    font-weight: 700;
                    text-transform: uppercase;
                    background-color: var(--paid-bg);
                    color: var(--paid-text);
                    padding: 2px 6px;
                    display: inline-block;
                    margin-top: 4px;
                    letter-spacing: 0.05em;
                }
                .unpaid-tag {
                    font-family: var(--font-mono);
                    font-size: 10px;
                    font-weight: 600;
                    text-transform: uppercase;
                    color: var(--text-muted);
                    padding: 2px 0;
                    display: inline-block;
                    margin-top: 4px;
                    letter-spacing: 0.05em;
                }
                /* Active Breakdown & Payment Panel */
                .active-panel {
                    display: none;
                    margin-top: 24px;
                    padding: 20px;
                    background-color: var(--surface);
                    border: 1px solid var(--border-dark);
                }
                .active-panel.visible {
                    display: block;
                    animation: fadeIn 0.2s ease-out;
                }
                @keyframes fadeIn {
                    from { opacity: 0; transform: translateY(-4px); }
                    to { opacity: 1; transform: translateY(0); }
                }
                .panel-title {
                    font-size: 20px;
                    font-weight: 700;
                    margin-bottom: 16px;
                }
                .breakdown-table {
                    width: 100%;
                    margin-bottom: 20px;
                }
                .breakdown-row {
                    display: flex;
                    justify-content: space-between;
                    align-items: flex-start;
                    padding: 8px 0;
                    font-size: 14px;
                    border-bottom: 1px solid var(--border);
                }
                .breakdown-row.total-row {
                    border-bottom: none;
                    border-top: 2px solid var(--border-dark);
                    margin-top: 8px;
                    padding-top: 12px;
                    font-size: 16px;
                    font-weight: 700;
                }
                .item-name-group {
                    display: flex;
                    flex-direction: column;
                }
                .item-split-note {
                    font-family: var(--font-mono);
                    font-size: 11px;
                    color: var(--text-secondary);
                }
                /* Buttons */
                .btn {
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    gap: 8px;
                    width: 100%;
                    padding: 16px;
                    font-family: var(--font-sans);
                    font-size: 15px;
                    font-weight: 600;
                    text-decoration: none;
                    cursor: pointer;
                    border: 1px solid var(--border-dark);
                    transition: opacity 0.15s ease, transform 0.05s ease;
                    border-radius: 0px;
                }
                .btn:active {
                    transform: scale(0.99);
                }
                .btn-primary {
                    background-color: var(--text);
                    color: var(--bg);
                }
                .btn-primary:hover {
                    opacity: 0.92;
                }
                .btn-secondary {
                    background-color: var(--bg);
                    color: var(--text);
                    margin-top: 8px;
                }
                .btn-secondary:hover {
                    background-color: var(--surface-hover);
                }
                .btn-apple-pay {
                    background-color: #000000;
                    color: #FFFFFF;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
                    font-weight: 600;
                    letter-spacing: -0.01em;
                }
                .btn-apple-pay svg {
                    height: 18px;
                    fill: currentColor;
                }
                /* Card Input form */
                .card-form {
                    display: none;
                    margin-top: 16px;
                    padding-top: 16px;
                    border-top: 1px solid var(--border);
                }
                .card-form.visible {
                    display: block;
                }
                .form-group {
                    margin-bottom: 12px;
                }
                .form-label {
                    display: block;
                    font-family: var(--font-mono);
                    font-size: 10px;
                    text-transform: uppercase;
                    letter-spacing: 0.05em;
                    color: var(--text-secondary);
                    margin-bottom: 4px;
                }
                .form-input {
                    width: 100%;
                    padding: 12px;
                    font-family: var(--font-mono);
                    font-size: 14px;
                    border: 1px solid var(--border);
                    background-color: var(--bg);
                    color: var(--text);
                    border-radius: 0;
                    outline: none;
                }
                .form-input:focus {
                    border-color: var(--border-dark);
                }
                .form-row {
                    display: flex;
                    gap: 8px;
                }
                /* Paid Confirmation Box */
                /* Paid Confirmation Box */
                .paid-box {
                    padding: 20px;
                    background-color: var(--text);
                    color: var(--bg);
                    text-align: center;
                    margin-top: 12px;
                }
                .paid-box-title {
                    font-size: 16px;
                    font-weight: 700;
                    margin-bottom: 6px;
                    font-family: var(--font-mono);
                    letter-spacing: 0.05em;
                }
                .paid-box-detail {
                    font-size: 13px;
                    opacity: 0.8;
                    font-family: var(--font-mono);
                }
                /* External Payment Methods - Plain Black Text Stack */
                .external-methods-container {
                    margin-top: 20px;
                    padding-top: 16px;
                    border-top: 1px solid var(--border);
                }
                .external-stack-title {
                    font-family: var(--font-mono);
                    font-size: 11px;
                    font-weight: 700;
                    text-transform: uppercase;
                    letter-spacing: 0.08em;
                    color: var(--text-secondary);
                    margin-bottom: 10px;
                }
                .payment-labels-stack {
                    display: flex;
                    flex-direction: column;
                    align-items: stretch;
                    gap: 0px;
                    background-color: var(--bg);
                    border: 1px solid var(--border);
                }
                .plain-text-payment-label {
                    background: none;
                    border: none;
                    border-bottom: 1px solid var(--border);
                    padding: 14px 16px;
                    font-family: var(--font-sans);
                    font-size: 16px;
                    font-weight: 600;
                    color: #000000;
                    cursor: pointer;
                    text-align: left;
                    text-decoration: none;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    width: 100%;
                    transition: background-color 0.15s ease;
                }
                .plain-text-payment-label:last-child {
                    border-bottom: none;
                }
                .plain-text-payment-label:hover {
                    background-color: var(--surface-hover);
                }
                .plain-text-payment-label .arrow-indicator {
                    font-family: var(--font-mono);
                    font-size: 14px;
                    color: var(--text-muted);
                }
                /* Instructions & Pending State */
                .instructions-box {
                    display: none;
                    margin-top: 14px;
                    padding: 14px;
                    background-color: var(--surface);
                    border: 1px solid var(--border-dark);
                    font-family: var(--font-mono);
                    font-size: 12px;
                    line-height: 1.6;
                    white-space: pre-wrap;
                }
                .pending-box {
                    display: none;
                    padding: 18px;
                    background-color: var(--surface);
                    border: 1px solid var(--border-dark);
                    text-align: center;
                    margin-top: 14px;
                }
                .pending-box-title {
                    font-family: var(--font-mono);
                    font-size: 13px;
                    font-weight: 700;
                    letter-spacing: 0.05em;
                    text-transform: uppercase;
                    margin-bottom: 6px;
                }
                .pending-box-detail {
                    font-size: 12px;
                    color: var(--text-secondary);
                    font-family: var(--font-mono);
                    margin-bottom: 14px;
                }
                .pending-tag {
                    font-family: var(--font-mono);
                    font-size: 10px;
                    font-weight: 600;
                    text-transform: uppercase;
                    color: #000000;
                    background-color: #F0F0F0;
                    border: 1px solid #000000;
                    padding: 2px 6px;
                    display: inline-block;
                    margin-top: 4px;
                    letter-spacing: 0.05em;
                }
                /* Accordion for Full Receipt */
                .receipt-accordion {
                    margin-top: 32px;
                    border: 1px solid var(--border);
                }
                .accordion-header {
                    padding: 14px 16px;
                    background-color: var(--bg);
                    cursor: pointer;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    font-family: var(--font-mono);
                    font-size: 12px;
                    font-weight: 600;
                    text-transform: uppercase;
                    letter-spacing: 0.05em;
                }
                .accordion-content {
                    display: none;
                    padding: 16px;
                    background-color: var(--surface);
                    border-top: 1px solid var(--border);
                }
                .accordion-content.open {
                    display: block;
                }
                .receipt-line {
                    display: flex;
                    justify-content: space-between;
                    padding: 6px 0;
                    font-size: 13px;
                }
                .receipt-line.sub-line {
                    color: var(--text-secondary);
                }
                .receipt-line.total-line {
                    font-weight: 700;
                    font-size: 14px;
                    border-top: 1px solid var(--border);
                    margin-top: 6px;
                    padding-top: 8px;
                }
                /* Context Selector */
                .context-selector-container {
                    margin-top: 14px;
                    padding-top: 4px;
                }
                .context-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    border-bottom: 1px solid var(--border-dark);
                    padding-bottom: 4px;
                    margin-bottom: 8px;
                }
                .context-options-grid {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 8px;
                }
                .context-option-btn {
                    background-color: var(--bg);
                    border: 1px solid var(--border);
                    color: var(--text);
                    font-family: var(--font-mono);
                    font-size: 11px;
                    padding: 10px 12px;
                    text-align: left;
                    cursor: pointer;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    border-radius: 0;
                    transition: background-color 0.15s ease, border-color 0.15s ease;
                }
                .context-option-btn:hover {
                    background-color: var(--surface);
                }
                .context-option-btn.selected {
                    background-color: var(--text);
                    color: var(--bg);
                    border-color: var(--border-dark);
                    font-weight: 700;
                }
                /* Toast notification */
                .toast {
                    position: fixed;
                    bottom: 24px;
                    left: 50%;
                    transform: translateX(-50%) translateY(100px);
                    background-color: var(--text);
                    color: var(--bg);
                    padding: 12px 24px;
                    font-family: var(--font-mono);
                    font-size: 12px;
                    font-weight: 600;
                    letter-spacing: 0.05em;
                    opacity: 0;
                    transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.25s ease;
                    z-index: 1000;
                    pointer-events: none;
                    text-transform: uppercase;
                }
                .toast.show {
                    transform: translateX(-50%) translateY(0);
                    opacity: 1;
                }
                /* Footer & Viral Loop */
                .footer {
                    margin-top: 48px;
                    padding-top: 24px;
                    border-top: 1px solid var(--border);
                    text-align: center;
                    font-family: var(--font-mono);
                    font-size: 11px;
                    color: var(--text-secondary);
                    letter-spacing: 0.05em;
                }
                .footer-invite-link {
                    color: var(--text);
                    text-decoration: underline;
                    text-underline-offset: 3px;
                    font-weight: 700;
                    text-transform: uppercase;
                    transition: opacity 0.15s ease;
                }
                .footer-invite-link:hover {
                    opacity: 0.7;
                }
                .footer-tagline {
                    display: block;
                    margin-top: 6px;
                    color: var(--text-muted);
                    font-size: 10px;
                    text-transform: uppercase;
                    letter-spacing: 0.06em;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <!-- Header -->
                <div class="header-section">
                    <div class="mono-label">Zippy · Bill Split</div>
                    <div class="price-lg price-mono">\(formatCurrency(receiptTotal))</div>
                    <div class="status-badge \(isAllPaid ? "all-paid" : "")" id="headerStatusBadge">
                        \(isAllPaid ? "✓ ALL SETTLED" : "\(paidCount) OF \(totalCount) SETTLED")
                    </div>

                    <!-- Progress -->
                    <div class="progress-bar-container">
                        <div class="progress-bar-fill" id="progressBarFill"></div>
                    </div>
                    <div class="progress-text">
                        <span id="collectedText">\(formatCurrency(totalCollected)) collected</span>
                        <span id="remainingText">\(formatCurrency(max(0, receiptTotal - totalCollected))) remaining</span>
                    </div>
                    <div style="margin-top: 10px; text-align: right;">
                        <a href="/s/\(token)/simplified" style="font-family: var(--font-mono); font-size: 11px; color: var(--text); text-decoration: underline; text-transform: uppercase; letter-spacing: 0.05em;">Simplified payments →</a>
                    </div>
                </div>

                <!-- Context Selector under thin black header -->
                <div class="context-selector-container">
                    <div class="context-header">
                        <span class="mono-label" style="color: var(--text);">CONTEXT</span>
                        <span id="currentCategoryLabel" style="font-family: var(--font-mono); font-size: 10px; color: var(--text-secondary); text-transform: uppercase;">\(session.category?.uppercased() ?? "OPTIONAL")</span>
                    </div>
                    <div class="context-options-grid" id="contextOptionsGrid">
                        <button type="button" class="context-option-btn \(session.category == "restaurants" ? "selected" : "")" onclick="setContextCategory('restaurants')">
                            <span>Restaurants</span>
                            <span class="indicator">\(session.category == "restaurants" ? "●" : "")</span>
                        </button>
                        <button type="button" class="context-option-btn \(session.category == "trips" ? "selected" : "")" onclick="setContextCategory('trips')">
                            <span>Trips</span>
                            <span class="indicator">\(session.category == "trips" ? "●" : "")</span>
                        </button>
                        <button type="button" class="context-option-btn \(session.category == "roommates" ? "selected" : "")" onclick="setContextCategory('roommates')">
                            <span>Roommates</span>
                            <span class="indicator">\(session.category == "roommates" ? "●" : "")</span>
                        </button>
                        <button type="button" class="context-option-btn \(session.category == "everyday" ? "selected" : "")" onclick="setContextCategory('everyday')">
                            <span>Everyday purchases</span>
                            <span class="indicator">\(session.category == "everyday" ? "●" : "")</span>
                        </button>
                    </div>
                </div>

                <div class="divider"></div>

                <!-- Who Are You Section -->
                <div class="section-title">Select Your Name</div>
                <div class="participant-list" id="participantList">
                    \(renderParticipantCards(balances: balances))
                </div>

                <!-- Active Personal Breakdown & Payment Panel -->
                <div class="active-panel" id="activePanel">
                    <div class="panel-title" id="activePersonTitle">Your Share</div>
                    
                    <div class="breakdown-table" id="breakdownItems">
                        <!-- Populated dynamically via JS -->
                    </div>

                    <!-- Payment Action Section -->
                    <div id="paymentActionContainer">
                        <!-- External Payment Methods: Plain Black Text Labels Stack -->
                        <div class="external-methods-container">
                            <div class="external-stack-title">External Payment Methods</div>
                            <div class="payment-labels-stack">
                                <button type="button" class="plain-text-payment-label" onclick="selectExternalMethod('Venmo')">
                                    <span>Venmo</span>
                                    <span class="arrow-indicator">→</span>
                                </button>
                                <button type="button" class="plain-text-payment-label" onclick="selectExternalMethod('PayPal')">
                                    <span>PayPal</span>
                                    <span class="arrow-indicator">→</span>
                                </button>
                                <button type="button" class="plain-text-payment-label" onclick="selectExternalMethod('Cash App')">
                                    <span>Cash App</span>
                                    <span class="arrow-indicator">→</span>
                                </button>
                                <button type="button" class="plain-text-payment-label" onclick="selectExternalMethod('Bank transfer')">
                                    <span>Bank transfer</span>
                                    <span class="arrow-indicator">→</span>
                                </button>
                            </div>
                        </div>

                        <!-- Bank Transfer / Deep Link Instructions -->
                        <div class="instructions-box" id="instructionsBox"></div>

                        <div class="divider" style="margin: 16px 0;"></div>

                        <!-- Apple Pay / Web Payment Request Button -->
                        <button class="btn btn-primary btn-apple-pay" id="btnApplePay" onclick="handlePaymentRequest()">
                            <svg viewBox="0 0 170 85" width="40" height="20">
                                <path d="M150.37 54.38c-.08-.18-.18-.34-.3-.49-1.28-1.52-2.92-2.28-4.9-2.28-1.92 0-3.53.76-4.83 2.28-.12.15-.22.31-.3.49-.07.18-.11.36-.11.55 0 .42.17.81.5 1.14.33.34.72.5 1.18.5.39 0 .73-.13 1.02-.39.29-.26.5-.59.62-.99.53-.59 1.19-.88 1.99-.88.75 0 1.39.29 1.92.88.13.4.34.73.63.99.29.26.63.39 1.02.39.46 0 .85-.16 1.18-.5.33-.33.5-.72.5-1.14 0-.19-.04-.37-.12-.55zm-105.74 3.7c1.35 1.57 3.06 2.36 5.12 2.36 1.77 0 3.32-.6 4.65-1.81 1.33-1.2 2.15-2.73 2.45-4.57.1-.64.16-1.3.16-1.98 0-.49-.03-1.02-.1-1.58h-7.16v2.16h4.63c-.31 1.25-.97 2.22-1.99 2.91-1.02.69-2.18 1.04-3.48 1.04-1.6 0-2.92-.6-3.95-1.8-1.04-1.2-1.55-2.75-1.55-4.65s.52-3.45 1.55-4.65c1.03-1.2 2.35-1.8 3.95-1.8 1.3 0 2.46.35 3.48 1.04 1.02.69 1.68 1.66 1.99 2.91h2.53c-.3-1.84-1.12-3.37-2.45-4.57-1.33-1.2-2.88-1.81-4.65-1.81-2.06 0-3.77.79-5.12 2.36-1.36 1.58-2.03 3.65-2.03 6.22 0 2.57.67 4.64 2.03 6.22z"/>
                            </svg>
                            <span id="applePayBtnText">Pay with Apple Pay</span>
                        </button>

                        <!-- Card Payment Toggle -->
                        <button class="btn btn-secondary" id="btnToggleCard" onclick="toggleCardForm()">
                            Pay with Debit / Credit Card
                        </button>

                        <!-- Inline Card Form -->
                        <div class="card-form" id="cardForm">
                            <div class="form-group">
                                <label class="form-label">Name on Card</label>
                                <input type="text" class="form-input" id="cardName" placeholder="Jane Doe" autocomplete="cc-name">
                            </div>
                            <div class="form-group">
                                <label class="form-label">Card Number</label>
                                <input type="text" class="form-input" id="cardNumber" placeholder="4242 4242 4242 4242" maxlength="19" autocomplete="cc-number">
                            </div>
                            <div class="form-row">
                                <div class="form-group" style="flex: 1;">
                                    <label class="form-label">Expires</label>
                                    <input type="text" class="form-input" id="cardExp" placeholder="MM/YY" maxlength="5" autocomplete="cc-exp">
                                </div>
                                <div class="form-group" style="flex: 1;">
                                    <label class="form-label">CVC</label>
                                    <input type="text" class="form-input" id="cardCvc" placeholder="123" maxlength="4" autocomplete="cc-csc">
                                </div>
                            </div>
                            <button class="btn btn-primary" style="margin-top: 8px;" onclick="submitCardPayment()">
                                Settle <span id="cardPayBtnAmount" class="price-mono">$0.00</span>
                            </button>
                        </div>

                        <!-- Mark as Settled / Cash Alternative -->
                        <button class="btn btn-secondary" style="border-style: dashed;" onclick="markSettledManually()">
                            Mark as Settled (Cash)
                        </button>
                    </div>

                    <!-- Pending State Display (Awaiting Webhook or Manual Confirmation) -->
                    <div class="pending-box" id="pendingConfirmationBox" style="display: none;">
                        <div class="pending-box-title">⏱ Awaiting Confirmation</div>
                        <div class="pending-box-detail" id="pendingConfirmationDetail">
                            Payment method recorded. Awaiting webhook or confirmation.
                        </div>
                        <button class="btn btn-primary" style="margin-top: 6px;" onclick="confirmManualSettlement()">
                            Confirm Settlement Manually
                        </button>
                    </div>

                    <!-- Paid State Display -->
                    <div class="paid-box" id="paidConfirmationBox" style="display: none;">
                        <div class="paid-box-title">✓ PAYMENT SETTLED</div>
                        <div class="paid-box-detail" id="paidConfirmationDetail">
                            Your balance has been recorded as paid.
                        </div>
                    </div>
                </div>

                <!-- Full Receipt Accordion -->
                <div class="receipt-accordion">
                    <div class="accordion-header" onclick="toggleAccordion()">
                        <span>View Full Itemized Receipt (\(receipt.items.count) Items)</span>
                        <span id="accordionChevron">↓</span>
                    </div>
                    <div class="accordion-content" id="accordionContent">
                        \(renderReceiptItems(receipt: receipt))
                        <div class="divider" style="margin: 12px 0;"></div>
                        <div class="receipt-line sub-line">
                            <span>Subtotal</span>
                            <span class="price-mono">\(formatCurrency(receipt.subtotal))</span>
                        </div>
                        <div class="receipt-line sub-line">
                            <span>Tax</span>
                            <span class="price-mono">\(formatCurrency(receipt.tax))</span>
                        </div>
                        <div class="receipt-line sub-line">
                            <span>Tip</span>
                            <span class="price-mono">\(formatCurrency(receipt.tip))</span>
                        </div>
                        <div class="receipt-line total-line">
                            <span>Total</span>
                            <span class="price-mono">\(formatCurrency(receipt.total))</span>
                        </div>
                    </div>
                </div>

                <!-- Viral Loop Footer: Discreet "Made with Zippy" with black text invite link -->
                <div class="footer">
                    <span>Made with </span><a href="\(baseURL)" class="footer-invite-link" target="_blank" rel="noopener noreferrer">Zippy</a>
                    <span class="footer-tagline">Split bills instantly · No app required</span>
                </div>
            </div>

            <!-- Toast -->
            <div class="toast" id="toast"></div>

            <script>
                // Data models passed from server
                const SESSION_TOKEN = "\(token)";
                const RECEIPT_ITEMS = \(renderItemsJSON(receipt: receipt));
                const ASSIGNMENTS = \(renderAssignmentsJSON(assignments: assignments));
                let BALANCES = \(sessionDataJSON);
                let selectedParticipantId = null;
                let currentCategory = "\(session.category ?? "")";

                // Format currency helper
                function formatMoney(amount) {
                    return '$' + (Number(amount) || 0).toFixed(2);
                }

                // Context Category Handler
                async function setContextCategory(cat) {
                    const newCategory = currentCategory === cat ? null : cat;
                    currentCategory = newCategory || "";
                    
                    const buttons = document.querySelectorAll('.context-option-btn');
                    const categories = ['restaurants', 'trips', 'roommates', 'everyday'];
                    buttons.forEach((btn, idx) => {
                        const c = categories[idx];
                        const isSel = (c === currentCategory);
                        btn.classList.toggle('selected', isSel);
                        const ind = btn.querySelector('.indicator');
                        if (ind) ind.textContent = isSel ? '●' : '';
                    });
                    
                    const label = document.getElementById('currentCategoryLabel');
                    if (label) {
                        label.textContent = currentCategory ? currentCategory.toUpperCase() : 'OPTIONAL';
                    }
                    showToast(currentCategory ? 'Context: ' + currentCategory : 'Context cleared');
                    
                    try {
                        await fetch('/s/' + SESSION_TOKEN + '/category', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ category: newCategory })
                        });
                    } catch (e) {
                        console.error('Failed to sync category:', e);
                    }
                }

                // Show toast notification
                function showToast(msg) {
                    const toast = document.getElementById('toast');
                    toast.textContent = msg;
                    toast.classList.add('show');
                    setTimeout(() => toast.classList.remove('show'), 3000);
                }

                // Toggle Full Receipt accordion
                function toggleAccordion() {
                    const content = document.getElementById('accordionContent');
                    const chevron = document.getElementById('accordionChevron');
                    const isOpen = content.classList.contains('open');
                    content.classList.toggle('open');
                    chevron.textContent = isOpen ? '↓' : '↑';
                }

                // Toggle card form
                function toggleCardForm() {
                    const form = document.getElementById('cardForm');
                    form.classList.toggle('visible');
                }

                // Format Card Input Helpers
                const cardInput = document.getElementById('cardNumber');
                if (cardInput) {
                    cardInput.addEventListener('input', function(e) {
                        let value = e.target.value.replace(/\\D/g, '');
                        value = value.replace(/(\\d{4})(?=\\d)/g, '$1 ');
                        e.target.value = value.substring(0, 19);
                    });
                }
                const expInput = document.getElementById('cardExp');
                if (expInput) {
                    expInput.addEventListener('input', function(e) {
                        let value = e.target.value.replace(/\\D/g, '');
                        if (value.length >= 2) {
                            value = value.substring(0, 2) + '/' + value.substring(2, 4);
                        }
                        e.target.value = value.substring(0, 5);
                    });
                }

                // Participant selection handler
                function selectParticipant(id) {
                    selectedParticipantId = id;
                    const person = BALANCES.find(p => p.participantId === id);
                    if (!person) return;

                    // Update selection highlight on cards
                    document.querySelectorAll('.participant-card').forEach(card => {
                        card.classList.toggle('selected', card.dataset.id === id);
                    });

                    // Reveal active panel
                    const panel = document.getElementById('activePanel');
                    panel.classList.add('visible');
                    panel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

                    document.getElementById('activePersonTitle').textContent = person.name + "'s Share";
                    document.getElementById('applePayBtnText').textContent = "Pay " + formatMoney(person.total) + " with Pay";
                    document.getElementById('cardPayBtnAmount').textContent = formatMoney(person.total);

                    // Build breakdown list
                    renderBreakdown(person);

                    // Toggle payment buttons vs pending confirmation vs paid confirmation
                    const actionContainer = document.getElementById('paymentActionContainer');
                    const pendingBox = document.getElementById('pendingConfirmationBox');
                    const pendingDetail = document.getElementById('pendingConfirmationDetail');
                    const paidBox = document.getElementById('paidConfirmationBox');
                    const paidDetail = document.getElementById('paidConfirmationDetail');

                    const isSettled = person.isPaid || person.settlementStatus === 'settled';
                    const isPending = !isSettled && (person.settlementStatus === 'pending_confirmation' || person.paymentMethod);

                    if (isSettled) {
                        actionContainer.style.display = 'none';
                        pendingBox.style.display = 'none';
                        paidBox.style.display = 'block';
                        const dateStr = person.paidAt ? new Date(person.paidAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
                        const method = person.paymentMethod || 'Settled';
                        paidDetail.textContent = formatMoney(person.total) + ' settled via ' + method + (dateStr ? ' at ' + dateStr : '');
                    } else if (isPending) {
                        actionContainer.style.display = 'block';
                        pendingBox.style.display = 'block';
                        paidBox.style.display = 'none';
                        const method = person.paymentMethod || 'External method';
                        pendingDetail.textContent = 'Selected: ' + method + ' (' + formatMoney(person.total) + '). Awaiting webhook or host confirmation.';
                    } else {
                        actionContainer.style.display = 'block';
                        pendingBox.style.display = 'none';
                        paidBox.style.display = 'none';
                    }
                }

                // Select External Payment Method (Venmo, PayPal, Cash App, Bank transfer)
                async function selectExternalMethod(method) {
                    const person = BALANCES.find(p => p.participantId === selectedParticipantId);
                    if (!person) return;

                    try {
                        const res = await fetch('/s/' + SESSION_TOKEN + '/select-payment-method', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                participantId: person.participantId,
                                paymentMethod: method
                            })
                        });

                        if (!res.ok) {
                            throw new Error('Failed to record method');
                        }

                        const data = await res.json();
                        person.paymentMethod = method;
                        person.settlementStatus = 'pending_confirmation';
                        person.isPaid = false;

                        showToast(method + ' selected · Awaiting confirmation');

                        // Handle instructions or deep link
                        const instrBox = document.getElementById('instructionsBox');
                        if (data.instructions) {
                            instrBox.textContent = data.instructions;
                            instrBox.style.display = 'block';
                        } else {
                            instrBox.style.display = 'none';
                        }

                        if (data.deepLink) {
                            window.open(data.deepLink, '_blank');
                        }

                        updateSummaryUI();
                        selectParticipant(person.participantId);
                    } catch (err) {
                        showToast('Error recording ' + method);
                    }
                }

                // Confirm settlement manually
                async function confirmManualSettlement() {
                    const person = BALANCES.find(p => p.participantId === selectedParticipantId);
                    if (!person) return;

                    try {
                        const res = await fetch('/s/' + SESSION_TOKEN + '/confirm', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                participantId: person.participantId,
                                confirmedBy: 'guest'
                            })
                        });

                        if (!res.ok) {
                            throw new Error('Confirmation failed');
                        }

                        const data = await res.json();
                        person.isPaid = true;
                        person.settlementStatus = 'settled';
                        person.paidAt = new Date().toISOString();

                        showToast('✓ Settlement Confirmed');
                        updateSummaryUI();
                        selectParticipant(person.participantId);
                    } catch (err) {
                        showToast('Failed to confirm settlement');
                    }
                }

                // Render item breakdown for selected participant
                function renderBreakdown(person) {
                    const container = document.getElementById('breakdownItems');
                    let html = '';

                    // Find assigned items
                    RECEIPT_ITEMS.forEach((item, index) => {
                        const assignees = ASSIGNMENTS[String(index)] || [];
                        if (assignees.includes(person.participantId)) {
                            const count = assignees.length;
                            const sharePrice = item.price / count;
                            const splitNote = count > 1 ? ' · Split ' + count + ' ways' : '';
                            html += `
                                <div class="breakdown-row">
                                    <div class="item-name-group">
                                        <span>${escapeHTML(item.name)}</span>
                                        <span class="item-split-note">${formatMoney(item.price)}${splitNote}</span>
                                    </div>
                                    <span class="price-mono">${formatMoney(sharePrice)}</span>
                                </div>
                            `;
                        }
                    });

                    // Items subtotal
                    html += `
                        <div class="breakdown-row" style="color: var(--text-secondary); padding-top: 12px;">
                            <span>Items Subtotal</span>
                            <span class="price-mono">${formatMoney(person.itemsSubtotal)}</span>
                        </div>
                        <div class="breakdown-row" style="color: var(--text-secondary);">
                            <span>Tax Share</span>
                            <span class="price-mono">${formatMoney(person.taxShare)}</span>
                        </div>
                        <div class="breakdown-row" style="color: var(--text-secondary);">
                            <span>Tip Share</span>
                            <span class="price-mono">${formatMoney(person.tipShare)}</span>
                        </div>
                        <div class="breakdown-row total-row">
                            <span>Total Due</span>
                            <span class="price-mono">${formatMoney(person.total)}</span>
                        </div>
                    `;

                    container.innerHTML = html;
                }

                function escapeHTML(str) {
                    return String(str).replace(/[&<>"']/g, function(m) {
                        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m];
                    });
                }

                // Web Payment Request API (Apple Pay / Google Pay)
                async function handlePaymentRequest() {
                    const person = BALANCES.find(p => p.participantId === selectedParticipantId);
                    if (!person) return;

                    // Check if browser supports standard Web Payment Request
                    if (window.PaymentRequest) {
                        const supportedPaymentMethods = [
                            {
                                supportedMethods: 'https://apple.com/apple-pay',
                                data: {
                                    version: 3,
                                    merchantIdentifier: 'merchant.app.zippy',
                                    countryCode: 'US',
                                    currencyCode: 'USD',
                                    supportedNetworks: ['visa', 'masterCard', 'amex', 'discover'],
                                    merchantCapabilities: ['supports3DS']
                                }
                            },
                            {
                                supportedMethods: 'basic-card',
                                data: {
                                    supportedNetworks: ['visa', 'masterCard', 'amex']
                                }
                            }
                        ];

                        const paymentDetails = {
                            total: {
                                label: 'Zippy Split - ' + person.name,
                                amount: { currency: 'USD', value: person.total.toFixed(2) }
                            }
                        };

                        try {
                            const request = new PaymentRequest(supportedPaymentMethods, paymentDetails);
                            const paymentResponse = await request.show();
                            // Process payment response
                            await processPayment(person.participantId, 'Apple Pay', paymentResponse.details?.transactionId || 'AP-' + Date.now());
                            await paymentResponse.complete('success');
                            return;
                        } catch (err) {
                            console.log('PaymentRequest dismissed or fallback triggered:', err);
                        }
                    }

                    // Direct 1-tap fallback simulation if PaymentRequest is unavailable/cancelled
                    await processPayment(person.participantId, 'Apple Pay', 'AP-' + Date.now());
                }

                // Card Payment Submission
                async function submitCardPayment() {
                    const person = BALANCES.find(p => p.participantId === selectedParticipantId);
                    if (!person) return;

                    const cardNum = document.getElementById('cardNumber').value.trim();
                    if (!cardNum) {
                        showToast('Please enter card details');
                        return;
                    }

                    await processPayment(person.participantId, 'Credit Card', 'CC-' + Date.now());
                }

                // Mark settled manually
                async function markSettledManually() {
                    const person = BALANCES.find(p => p.participantId === selectedParticipantId);
                    if (!person) return;

                    await processPayment(person.participantId, 'Cash / Settlement', 'MANUAL-' + Date.now());
                }

                // Process payment via backend API
                async function processPayment(participantId, method, ref) {
                    try {
                        const res = await fetch('/s/' + SESSION_TOKEN + '/pay', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                participantId: participantId,
                                paymentMethod: method,
                                transactionReference: ref
                            })
                        });

                        if (!res.ok) {
                            throw new Error('Payment processing failed');
                        }

                        const data = await res.json();
                        showToast('Payment Settled');
                        
                        // Update local balance state
                        const person = BALANCES.find(p => p.participantId === participantId);
                        if (person) {
                            person.isPaid = true;
                            person.settlementStatus = 'settled';
                            person.paidAt = new Date().toISOString();
                            person.paymentMethod = method;
                        }

                        // Re-render UI
                        updateSummaryUI();
                        selectParticipant(participantId);
                    } catch (err) {
                        showToast('Failed to record payment');
                    }
                }

                // Live status polling
                async function pollStatus() {
                    try {
                        const res = await fetch('/s/' + SESSION_TOKEN + '/status');
                        if (res.ok) {
                            const data = await res.json();
                            if (data.participants) {
                                data.participants.forEach(p => {
                                    const local = BALANCES.find(b => b.participantId === p.id);
                                    if (local) {
                                        local.isPaid = p.isPaid;
                                        local.settlementStatus = p.settlementStatus;
                                        local.paidAt = p.paidAt;
                                        local.paymentMethod = p.paymentMethod;
                                    }
                                });
                                updateSummaryUI();
                                if (selectedParticipantId) {
                                    selectParticipant(selectedParticipantId);
                                }
                            }
                        }
                    } catch (e) {
                        // ignore network blips in background polling
                    }
                }

                // Update summary metrics & participant badges
                function updateSummaryUI() {
                    const paidBalances = BALANCES.filter(b => b.isPaid || b.settlementStatus === 'settled');
                    const paidCount = paidBalances.length;
                    const totalCount = BALANCES.length;
                    const totalCollected = paidBalances.reduce((sum, b) => sum + b.total, 0);
                    const totalDue = BALANCES.reduce((sum, b) => sum + b.total, 0);
                    const percent = totalCount > 0 ? (paidCount / totalCount) * 100 : 0;
                    const isAllPaid = totalCount > 0 && paidCount === totalCount;

                    // Progress bar
                    const fill = document.getElementById('progressBarFill');
                    if (fill) fill.style.width = percent + '%';

                    // Header badge
                    const badge = document.getElementById('headerStatusBadge');
                    if (badge) {
                        badge.textContent = isAllPaid ? '✓ ALL SETTLED' : paidCount + ' OF ' + totalCount + ' SETTLED';
                        badge.classList.toggle('all-paid', isAllPaid);
                    }

                    // Progress labels
                    const collectedText = document.getElementById('collectedText');
                    if (collectedText) collectedText.textContent = formatMoney(totalCollected) + ' collected';

                    const remainingText = document.getElementById('remainingText');
                    if (remainingText) remainingText.textContent = formatMoney(Math.max(0, totalDue - totalCollected)) + ' remaining';

                    // Update participant card badges
                    BALANCES.forEach(b => {
                        const card = document.querySelector(`.participant-card[data-id="${b.participantId}"]`);
                        if (card) {
                            const tagContainer = card.querySelector('.status-tag-container');
                            if (tagContainer) {
                                if (b.isPaid || b.settlementStatus === 'settled') {
                                    tagContainer.innerHTML = '<span class="paid-tag">✓ PAID</span>';
                                } else if (b.settlementStatus === 'pending_confirmation' || b.paymentMethod) {
                                    tagContainer.innerHTML = '<span class="pending-tag">AWAITING CONFIRMATION</span>';
                                } else {
                                    tagContainer.innerHTML = '<span class="unpaid-tag">UNPAID</span>';
                                }
                            }
                        }
                    });
                }

                // Check URL query param for pre-selection (e.g. ?p=UUID)
                window.addEventListener('DOMContentLoaded', () => {
                    const urlParams = new URLSearchParams(window.location.search);
                    const preselectedId = urlParams.get('p');
                    if (preselectedId && BALANCES.some(b => b.participantId === preselectedId)) {
                        selectParticipant(preselectedId);
                    }

                    // Start background polling every 4 seconds
                    setInterval(pollStatus, 4000);
                });
            </script>
        </body>
        </html>
        """
    }

    // MARK: - HTML Generation Helpers

    private static func renderParticipantCards(balances: [PersonBalanceDTO]) -> String {
        return balances.map { balance in
            let initial = String(balance.name.prefix(1)).uppercased()
            let statusTag: String
            if balance.isPaid || balance.settlementStatus == .settled {
                statusTag = "<span class=\"paid-tag\">✓ PAID</span>"
            } else if balance.settlementStatus == .pendingConfirmation || balance.paymentMethod != nil {
                statusTag = "<span class=\"pending-tag\">AWAITING CONFIRMATION</span>"
            } else {
                statusTag = "<span class=\"unpaid-tag\">UNPAID</span>"
            }

            return """
            <div class="participant-card" data-id="\(balance.participantId.uuidString)" onclick="selectParticipant('\(balance.participantId.uuidString)')">
                <div class="card-header">
                    <div class="person-info">
                        <div class="person-avatar">\(initial)</div>
                        <div class="person-name">\(escapeHTML(balance.name))</div>
                    </div>
                    <div class="person-amount">
                        <div class="person-total">\(formatCurrency(balance.total))</div>
                        <div class="status-tag-container">\(statusTag)</div>
                    </div>
                </div>
            </div>
            """
        }.joined(separator: "\n")
    }

    private static func renderReceiptItems(receipt: ExtractedReceipt) -> String {
        return receipt.items.map { item in
            let qtyNote = item.quantity > 1 ? "<span style=\"color: var(--text-muted); font-size: 11px;\"> ×\(item.quantity)</span>" : ""
            return """
            <div class="receipt-line">
                <span>\(escapeHTML(item.name))\(qtyNote)</span>
                <span class="price-mono">\(formatCurrency(item.price))</span>
            </div>
            """
        }.joined(separator: "\n")
    }

    private static func renderItemsJSON(receipt: ExtractedReceipt) -> String {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(receipt.items)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }

    private static func renderAssignmentsJSON(assignments: [String: [UUID]]) -> String {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(assignments)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    private static func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Renders a stark white screen displaying the reduced list of black text lines titled "Simplified payments".
    public static func renderSimplifiedPayments(lines: [String], title: String = "Simplified payments", backURL: String? = nil, baseURL: String? = nil) -> String {
        let linesHTML = lines.map { line in
            "<li class=\"payment-line\">\(escapeHTML(line))</li>"
        }.joined(separator: "\n")

        let backLinkHTML = backURL != nil ? "<a href=\"\(backURL!)\" class=\"back-link\">← Back to bill</a>" : ""
        let appLandingURL = baseURL ?? "/"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <meta name="theme-color" content="#FFFFFF">
            <title>\(escapeHTML(title))</title>
            <style>
                *, *::before, *::after {
                    box-sizing: border-box;
                    margin: 0;
                    padding: 0;
                    -webkit-font-smoothing: antialiased;
                }
                body {
                    background-color: #FFFFFF;
                    color: #000000;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Mono", Menlo, Monaco, Consolas, "Segoe UI", Roboto, sans-serif;
                    line-height: 1.6;
                    min-height: 100vh;
                    padding: 48px 24px 64px 24px;
                }
                .container {
                    max-width: 480px;
                    margin: 0 auto;
                }
                h1 {
                    font-size: 28px;
                    font-weight: 700;
                    letter-spacing: -0.03em;
                    color: #000000;
                    margin-bottom: 32px;
                }
                .payment-list {
                    list-style: none;
                    margin: 0;
                    padding: 0;
                }
                .payment-line {
                    font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
                    font-size: 16px;
                    font-weight: 500;
                    color: #000000;
                    padding: 16px 0;
                    border-bottom: 1px solid #EAEAEA;
                }
                .payment-line:last-child {
                    border-bottom: none;
                }
                .back-link {
                    display: inline-block;
                    margin-top: 32px;
                    font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
                    font-size: 13px;
                    color: #000000;
                    text-decoration: underline;
                    text-transform: uppercase;
                    letter-spacing: 0.05em;
                }
                .back-link:hover {
                    opacity: 0.7;
                }
                /* Footer & Viral Loop */
                .footer {
                    margin-top: 48px;
                    padding-top: 24px;
                    border-top: 1px solid #EAEAEA;
                    text-align: center;
                    font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
                    font-size: 11px;
                    color: #6B6B6B;
                    letter-spacing: 0.05em;
                }
                .footer-invite-link {
                    color: #000000;
                    text-decoration: underline;
                    text-underline-offset: 3px;
                    font-weight: 700;
                    text-transform: uppercase;
                    transition: opacity 0.15s ease;
                }
                .footer-invite-link:hover {
                    opacity: 0.7;
                }
                .footer-tagline {
                    display: block;
                    margin-top: 6px;
                    color: #8E8E8E;
                    font-size: 10px;
                    text-transform: uppercase;
                    letter-spacing: 0.06em;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>\(escapeHTML(title))</h1>
                <ul class="payment-list">
                    \(linesHTML)
                </ul>
                \(backLinkHTML)

                <!-- Viral Loop Footer -->
                <div class="footer">
                    <span>Made with </span><a href="\(appLandingURL)" class="footer-invite-link" target="_blank" rel="noopener noreferrer">Zippy</a>
                    <span class="footer-tagline">Split bills instantly · No app required</span>
                </div>
            </div>
        </body>
        </html>
        """
    }
}


