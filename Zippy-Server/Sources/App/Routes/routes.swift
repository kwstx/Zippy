import Vapor

func routes(_ app: Application) throws {
    let receiptController = ReceiptController()
    let splitController = SplitController()
    let groupController = GroupController()
    
    app.group("api") { api in
        api.group("groups") { groups in
            groups.get(use: groupController.list)
            groups.post(use: groupController.create)
            groups.get(":id", use: groupController.get)
            groups.get(":id", "history", use: groupController.getHistory)
            groups.get(":id", "ledger", use: groupController.getHistory)
            groups.post(":id", "expenses", use: groupController.addExpense)
            groups.post(":id", "settlements", use: groupController.addSettlement)
            groups.delete(":id", use: groupController.delete)
        }
        
        api.group("receipts") { receipts in
            receipts.get(use: receiptController.list)
            receipts.post("upload", use: receiptController.upload)
            receipts.post("manual", use: receiptController.createManual)
            receipts.post(":referenceId", "extract", use: receiptController.extract)
            receipts.get(":id", "result", use: receiptController.getResult)
            receipts.patch(":id", use: receiptController.patchReceipt)
            receipts.patch(":id", "category", use: receiptController.updateCategory)
        }
        
        api.group("splits") { splits in
            splits.get(use: splitController.getHistory)
            splits.get("history", use: splitController.getHistory)
            splits.post(use: splitController.create)
            splits.get(":id", use: splitController.get)
            splits.patch(":id", "category", use: splitController.updateCategory)
            splits.get("token", ":token", use: splitController.getByToken)
            splits.post("simplify", use: splitController.simplifyExpenses)
            splits.get(":token", "simplified", use: splitController.getSimplifiedPayments)
            splits.post(":token", "pay", use: splitController.processGuestPayment)
            splits.post(":token", "select-payment-method", use: splitController.selectPaymentMethod)
            splits.post(":token", "confirm", use: splitController.confirmSettlement)
            splits.post(":token", "category", use: splitController.updateCategory)
            splits.post("webhook", use: splitController.handleWebhook)
            splits.get(":token", "status", use: splitController.getStatus)
        }

        api.group("webhooks") { webhooks in
            webhooks.post("payment", use: splitController.handleWebhook)
        }
    }
    
    // Short URL shareable guest endpoints (unauthenticated web access)
    app.group("s", ":token") { guest in
        guest.get(use: splitController.getByToken)
        guest.get("view", use: splitController.viewGuestHTML)
        guest.get("simplified", use: splitController.getSimplifiedPayments)
        guest.post("pay", use: splitController.processGuestPayment)
        guest.post("select-payment-method", use: splitController.selectPaymentMethod)
        guest.post("confirm", use: splitController.confirmSettlement)
        guest.post("category", use: splitController.updateCategory)
        guest.get("status", use: splitController.getStatus)
    }

    // Direct standalone public route for Simplified Payments
    app.get("simplified-payments", use: splitController.viewSimplifiedPaymentsStandalone)
}


