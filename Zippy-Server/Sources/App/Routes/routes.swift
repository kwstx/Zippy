import Vapor

func routes(_ app: Application) throws {
    let receiptController = ReceiptController()
    
    app.group("api") { api in
        api.group("receipts") { receipts in
            receipts.post("upload", use: receiptController.upload)
            receipts.post(":referenceId", "extract", use: receiptController.extract)
            receipts.get(":id", "result", use: receiptController.getResult)
        }
    }
}
