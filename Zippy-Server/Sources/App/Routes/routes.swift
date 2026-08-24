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
        }
    }
}
