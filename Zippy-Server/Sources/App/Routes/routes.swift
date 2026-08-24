import Vapor

func routes(_ app: Application) throws {
    let receiptController = ReceiptController()
    let splitController = SplitController()
    
    app.group("api") { api in
        api.group("receipts") { receipts in
            receipts.post("upload", use: receiptController.upload)
            receipts.post(":referenceId", "extract", use: receiptController.extract)
            receipts.get(":id", "result", use: receiptController.getResult)
        }
        
        api.group("splits") { splits in
            splits.post(use: splitController.create)
            splits.get(":id", use: splitController.get)
            splits.get("token", ":token", use: splitController.getByToken)
            splits.post(":token", "pay", use: splitController.processGuestPayment)
            splits.get(":token", "status", use: splitController.getStatus)
        }
    }
    
    // Short URL shareable guest endpoints (unauthenticated web access)
    app.group("s", ":token") { guest in
        guest.get(use: splitController.getByToken)
        guest.get("view", use: splitController.viewGuestHTML)
        guest.post("pay", use: splitController.processGuestPayment)
        guest.get("status", use: splitController.getStatus)
    }
}

