import Vapor

func routes(_ app: Application) throws {
    let receiptController = ReceiptController()
    
    app.group("api") { api in
        api.group("receipts") { receipts in
            receipts.post("upload", use: receiptController.upload)
        }
    }
}
