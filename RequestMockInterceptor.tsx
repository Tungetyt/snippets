import { setupWorker } from "msw";
import React from "react";
import { NodeEnv } from "src/utils/consts";

const INTERCEPT_REQUEST_IN_DEVELOPMENT =
    process.env.NODE_ENV === NodeEnv.Development &&
    process.env.REACT_APP_MSW_INTERCEPT_REQUEST_IN_DEVELOPMENT === "true";

/**
 * MSW  in development
You can use the same mocks for server handlers in testing as well as development. So you don't have to rely on real server in development. If it is enabled, then all requests, that match handlers are automatically intercepted.
Steps to enable MSW in development

1. Create .env.development.local file in root folder.
2. Paste REACT_APP_MSW_INTERCEPT_REQUEST_IN_DEVELOPMENT = true in the created file
3. Start the application with yarn start pasted in the terminal
4. Close all browsers
5. Open up your browser with "C:\Program Files\Google\Chrome\Application\chrome.exe" --ignore-certificate-errors --unsafely-treat-insecure-origin-as-secure=https://localhost:1123 pasted in the terminal.
6. Navigate to https://localhost:3000 or with other port used by your application 
 */
const RequestMockInterceptor = () => {
    if (!INTERCEPT_REQUEST_IN_DEVELOPMENT) return null;

    const { handlers } = require("../test/server-handlers");
    setupWorker(...handlers).start();

    return (
        <aside
            style={{
                textAlign: "center",
                left: 0,
                right: 0,
                top: 0,
                position: "fixed",
                zIndex: 999999999,
                color: "white",
                backgroundColor: "darkred",
                opacity: 0.3,
                fontWeight: "bolder",
                userSelect: "none",
                pointerEvents: "none",
            }}
        >
            USING MOCKS
        </aside>
    );
};

export default RequestMockInterceptor;
