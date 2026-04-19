# interview-creator

## 🚀 How to Run Locally

To run this application locally, you will need two separate terminal windows: one for the Internet Computer backend and one for the React frontend.

### Prerequisites
Make sure you have an OpenAI API Key. Export it in your terminal before deploying the backend:
\`\`\`bash
export OPENAI_API_KEY="your-api-key-here"
\`\`\`

### 1. Start the Backend (Terminal 1)
First, start the local Internet Computer replica in the background:
\`\`\`bash
dfx start --background
\`\`\`

Once the network is running, deploy the backend canister and pass your OpenAI API key as an argument:
\`\`\`bash
dfx deploy backend --argument "( \"$OPENAI_API_KEY\" )"
\`\`\`

### 2. Start the Frontend (Terminal 2)
Open a new terminal window, navigate to the frontend directory, and start the Vite development server:
\`\`\`bash
cd src/frontend
npm install
npm run dev
\`\`\`

The frontend will start running locally (usually at `http://localhost:5173`). 

### 🛑 Stopping the Application
When you are done developing, you can gracefully stop the local Internet Computer network by running:
\`\`\`bash
dfx stop
\`\`\`
