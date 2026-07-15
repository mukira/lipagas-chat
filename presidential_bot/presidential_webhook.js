const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const truecallerjs = require('truecallerjs');
require('dotenv').config({ path: '/root/sentiment_analysis/.env' });

const app = express();
app.use(bodyParser.json());

const PORT = process.env.PORT || 3001;

// Internal API for Typebot to trigger the silent OSINT profiler
app.post('/api/profile', (req, res) => {
    // Fast response so Typebot continues its flow without waiting
    res.sendStatus(200);

    const body = req.body;
    const phone = body.phone;
    const metaProfileName = body.name || "Unknown";

    if (!phone) {
        console.error('[Internal API] Missing phone number in request.');
        return;
    }

    let osintData = { name: metaProfileName, carrier: "Unknown", location: "Unknown", truecallerName: "Unknown" };

    // 1. Fetch OSINT Data silently
    try {
        console.log(`[OSINT] Extracted Name for ${phone}: ${metaProfileName}`);
    } catch(err) {
        console.error('[OSINT] Truecaller extraction failed:', err.message);
    }

    // 2. Trigger AI Profiler in the background
    try {
        const scriptPath = __dirname + '/scripts/osint_profiler.py';
        const cmd = `python3 ${scriptPath} "${phone}" "${osintData.name}" "${osintData.truecallerName}" "${osintData.location}" "${osintData.carrier}"`;
        
        exec(cmd, (error, stdout, stderr) => {
            if (error) {
                console.error(`[Profiler Error] ${error.message}`);
                return;
            }
            if (stderr) {
                console.error(`[Profiler Stderr] ${stderr}`);
            }
            console.log(`[Profiler Success] ${stdout}`);
        });
    } catch(err) {
        console.error('Bot Error:', err.message);
    }
});

const { Client } = require('pg');
app.get('/api/get-profile', async (req, res) => {
    const phone = req.query.phone;
    if (!phone) {
        return res.json({ message: "Error: No phone number provided." });
    }

    const client = new Client({ connectionString: process.env.DATABASE_URL });
    try {
        await client.connect();
        const result = await client.query("SELECT * FROM citizen_profiles WHERE phone_number = $1", [phone]);
        
        if (result.rows.length === 0) {
            return res.json({ message: "No profile data found for your number yet. Please try again later." });
        }
        
        const profile = result.rows[0];
        const interests = profile.estimated_interests ? profile.estimated_interests.join(", ") : "None";
        
        const text = `*Your Secret Profile*\n\n📱 *Phone:* ${profile.phone_number}\n👤 *Meta Name:* ${profile.meta_name}\n📞 *Truecaller Name:* ${profile.truecaller_name || 'Unknown'}\n📍 *Location:* ${profile.location || 'Unknown'}\n📡 *Carrier:* ${profile.carrier || 'Unknown'}\n\n🧠 *Gemini Profiled Interests:*\n${interests}`;
        
        res.json({ message: text });
    } catch (err) {
        console.error("[DB Error]", err.message);
        res.json({ message: "Error retrieving profile data." });
    } finally {
        await client.end();
    }
});

app.listen(PORT, () => {
    console.log(`Presidential Internal API is listening on port ${PORT}`);
});
