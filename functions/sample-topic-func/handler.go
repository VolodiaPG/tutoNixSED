package function

import (
	"fmt"
)

// Handle a serverless request
func Handle(req []byte) string {
	println("Hello, Go. You said: %s", string(req))
	return fmt.Sprintf("Hello, Go. You said: %s", string(req))
}
