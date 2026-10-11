package com.plaidtest.cardsemble

import android.app.Notification
import android.os.Build
import android.service.notification.StatusBarNotification
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import java.lang.reflect.Method

@RunWith(AndroidJUnit4::class)
class GooglePayNotificationParserTest {

    @Test
    fun parseTransaction_standardUsdWithVisaLast4() {
        val service = GooglePayNotificationListenerService()
        val title = "Starbucks"
        val text = "Visa ending **** 1234  \$12.50"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Starbucks", result!!.merchant)
        assertEquals("12.50", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Visa ending 1234", result.cardLabel)
    }

    @Test
    fun parseTransaction_mastercardWithDollarAmount() {
        val service = GooglePayNotificationListenerService()
        val title = "Whole Foods Market"
        val text = "Mastercard **** 5678  \$85.43"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Whole Foods Market", result!!.merchant)
        assertEquals("85.43", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Mastercard ending 5678", result.cardLabel)
    }

    @Test
    fun parseTransaction_eurWithSymbol() {
        val service = GooglePayNotificationListenerService()
        val title = "Pret A Manger"
        val text = "Visa ending **** 9999  €15.50"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Pret A Manger", result!!.merchant)
        assertEquals("15.50", result.amount)
        assertEquals("EUR", result.currency)
        assertEquals("Visa ending 9999", result.cardLabel)
    }

    @Test
    fun parseTransaction_gbpWithSymbol() {
        val service = GooglePayNotificationListenerService()
        val title = "Tesco"
        val text = "Amex **** 1111  £23.45"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Tesco", result!!.merchant)
        assertEquals("23.45", result.amount)
        assertEquals("GBP", result.currency)
        assertEquals("Amex ending 1111", result.cardLabel)
    }

    @Test
    fun parseTransaction_currencyCodeFormat() {
        val service = GooglePayNotificationListenerService()
        val title = "Amazon.com"
        val text = "Visa  99.99 USD"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Amazon.com", result!!.merchant)
        assertEquals("99.99", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Visa", result.cardLabel)
    }

    @Test
    fun parseTransaction_jpyWithSymbol() {
        val service = GooglePayNotificationListenerService()
        val title = "7-Eleven"
        val text = "JCB  ¥1250"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("7-Eleven", result!!.merchant)
        assertEquals("1250.00", result.amount)
        assertEquals("JPY", result.currency)
        assertEquals("Google Pay", result.cardLabel)
    }

    @Test
    fun parseTransaction_jpyWithCurrencyCode() {
        val service = GooglePayNotificationListenerService()
        val title = "7-Eleven"
        val text = "JCB  1250 JPY"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("7-Eleven", result!!.merchant)
        assertEquals("1250.00", result.amount)
        assertEquals("JPY", result.currency)
        assertEquals("Google Pay", result.cardLabel)
    }

    @Test
    fun parseTransaction_noCardLast4() {
        val service = GooglePayNotificationListenerService()
        val title = "Uber"
        val text = "Visa  \$24.99"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Uber", result!!.merchant)
        assertEquals("24.99", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Visa", result.cardLabel)
    }

    @Test
    fun parseTransaction_discoverCard() {
        val service = GooglePayNotificationListenerService()
        val title = "Target"
        val text = "Discover ending **** 4321  \$67.89"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Target", result!!.merchant)
        assertEquals("67.89", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Discover ending 4321", result.cardLabel)
    }

    @Test
    fun parseTransaction_americanExpressFullName() {
        val service = GooglePayNotificationListenerService()
        val title = "Delta Airlines"
        val text = "American Express **** 5555  \$299.00"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Delta Airlines", result!!.merchant)
        assertEquals("299.00", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("AmericanExpress ending 5555", result.cardLabel)
    }

    @Test
    fun parseTransaction_masterCardTwoWords() {
        val service = GooglePayNotificationListenerService()
        val title = "Best Buy"
        val text = "Master Card **** 7777  \$149.99"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Best Buy", result!!.merchant)
        assertEquals("149.99", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("MasterCard ending 7777", result.cardLabel)
    }

    @Test
    fun parseTransaction_chargeFormat() {
        val service = GooglePayNotificationListenerService()
        val title = "Walmart"
        val text = "Charge of \$42.15 to Visa **** 1234"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Walmart", result!!.merchant)
        assertEquals("42.15", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Visa ending 1234", result.cardLabel)
    }

    @Test
    fun parseTransaction_youPaidFormat() {
        val service = GooglePayNotificationListenerService()
        val title = "Shell"
        val text = "You paid \$35.00 with Mastercard ending **** 9876"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Shell", result!!.merchant)
        assertEquals("35.00", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Mastercard ending 9876", result.cardLabel)
    }

    @Test
    fun parseTransaction_underOneDollar() {
        val service = GooglePayNotificationListenerService()
        val title = "Small Purchase"
        val text = "\$0.99"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Small Purchase", result!!.merchant)
        assertEquals("0.99", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Google Pay", result.cardLabel)
    }

    @Test
    fun parseTransaction_withCommaSeparator() {
        val service = GooglePayNotificationListenerService()
        val title = "Large Purchase"
        val text = "\$1,234.56"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Large Purchase", result!!.merchant)
        assertEquals("1234.56", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Google Pay", result.cardLabel)
    }

    @Test
    fun parseTransaction_multiLineText() {
        val service = GooglePayNotificationListenerService()
        val title = "Costco"
        val text = "Visa **** 1111\n\$123.45\nApproved"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("Costco", result!!.merchant)
        assertEquals("123.45", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Visa ending 1111", result.cardLabel)
    }

    @Test
    fun parseTransaction_emptyTitle() {
        val service = GooglePayNotificationListenerService()
        val title = ""
        val text = "Visa **** 1234  \$50.00"

        val result = invokeParseTransaction(service, title, text)

        assertNotNull(result)
        assertEquals("", result!!.merchant)
        assertEquals("50.00", result.amount)
        assertEquals("USD", result.currency)
        assertEquals("Visa ending 1234", result.cardLabel)
    }

    private fun invokeParseTransaction(
        service: GooglePayNotificationListenerService,
        title: String,
        text: String
    ): GooglePayNotificationListenerService.ParsedTransaction? {
        val method: Method = GooglePayNotificationListenerService::class.java.getDeclaredMethod(
            "parseTransaction",
            String::class.java,
            String::class.java
        )
        method.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        return method.invoke(service, title, text) as? GooglePayNotificationListenerService.ParsedTransaction
    }
}