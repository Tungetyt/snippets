type Result<A, E> = Success<A, E> | Failure<A, E>

interface IResult<A, E> {
	readonly _tag: 'Success' | 'Failure'
	isSuccess(): this is Success<A, E>
	map<B>(f: (a: A) => B): Result<B, E>
	flatMap<B, E2>(f: (a: A) => Result<B, E2>): Result<B, E | E2>
}

class Success<A, E> implements IResult<A, E> {
	readonly _tag = 'Success'
	constructor(readonly value: A) {}

	isSuccess(): this is Success<A, E> {
		return true
	}

	map<B>(f: (a: A) => B): Result<B, E> {
		return new Success(f(this.value))
	}

	flatMap<B, E2>(f: (a: A) => Result<B, E2>): Result<B, E | E2> {
		return f(this.value)
	}
}

class Failure<A, E> implements IResult<A, E> {
	readonly _tag = 'Failure'
	constructor(readonly error: E) {}

	isSuccess(): this is Success<A, E> {
		return true
	}

	map<B>(_f: (a: A) => B): Result<B, E> {
		// @ts-expect-error
		return this
	}

	flatMap<B, E2>(_f: (a: A) => Result<B, E2>): Result<B, E | E2> {
		// @ts-expect-error
		return this
	}
}

type ErrorWithMessage = {
	message: string
}

function isErrorWithMessage(error: unknown): error is ErrorWithMessage {
	return (
		typeof error === 'object' &&
		error !== null &&
		'message' in error &&
		typeof (error as Record<string, unknown>)["message"] === 'string'
	)
}

function toErrorWithMessage(maybeError: unknown): ErrorWithMessage {
	if (isErrorWithMessage(maybeError)) return maybeError

	try {
		return new Error(JSON.stringify(maybeError))
	} catch {
		// fallback in case there's an error stringifying the maybeError
		// like with circular references for example.
		return new Error(String(maybeError))
	}
}

function getErrorMessage(error?: unknown) {
    if(!error) return ""
	return toErrorWithMessage(error).message
}

abstract class CustomError {
	protected abstract readonly _tag: `${string}Error`
	readonly message: string

    constructor(readonly error?: unknown) {
        this.message = getErrorMessage(error)
    }
}

class InvalidJsonError extends CustomError {
	protected readonly _tag = 'InvalidJsonError'
}

class RequestFailedError extends CustomError {
	protected readonly _tag = 'RequestFailedError'
}

class TimeoutError extends CustomError {
	protected readonly _tag = 'TimeoutError'
}

class ValidationError extends CustomError {
	protected readonly _tag = 'ValidationError'
}

class UnknownError extends CustomError {
	protected readonly _tag = 'UnknownError'
}

type Fetch = Parameters<typeof fetch>
type Input = Fetch[0]
type Init = Fetch[1]

type Prettify<T> = {
	[K in keyof T]: T[K]
} & {}

type Timeout = Prettify<{
	ms: number
	signal: AbortSignal
}>

type NoEmptyString<T extends string | Input> = T extends '' ? never : T

const getController = ({ms, signal}: Timeout) => {
	const controller = new AbortController()
	setTimeout(() => controller.abort(), ms)
	signal.addEventListener('abort', () => controller.abort())

	return controller
}

async function doFetch<I extends Input, T>(
	input: NoEmptyString<I>,
	{
		init,
		retries = 3,
		retryBaseDelay = 1000,
		timeout,
		validator
	}: {
		init?: Prettify<Omit<Exclude<Init, undefined>, 'signal'>>
		retries?: number
		retryBaseDelay?: number
		timeout?: Timeout
		validator: (data: T) => boolean
	}
) {
    try {
        async function execute(attempt: number) {
            try {
                const response = await fetch(input, {
                    ...init,
                    signal: (timeout && getController(timeout).signal) ?? null
                })
                if (!response.ok) throw new Error('Not OK!')
    
                let data: T
                try {
                    data = await response.json()
                } catch (jsonError) {
                    if (attempt < retries) throw jsonError // jump to retry
                    return new Failure(new InvalidJsonError())
                }
    
                if (validator(data)) return new Success(data)
    
                return new Failure(new ValidationError())
            } catch (error) {
                if ((error as Error).name === 'AbortError')
                    return new Failure(new TimeoutError())
    
                if (attempt < retries) {
                    const delayMs = retryBaseDelay * 2 ** attempt
                    await new Promise(resolve => setTimeout(resolve, delayMs))
                    return await execute(attempt + 1)
                }
    
                return new Failure(new RequestFailedError())
            }
        }
    
        return execute(0)
    } catch(e) {
        return new Failure(new UnknownError(e))
    }
}

// Example usage: Promise chain:
doFetch('/api/v1/users', {
	validator: (data: {userName: 'abc'}) => true
}).then(result => {
	if (result.isSuccess()) {
		console.log('Data:', result.value.userName)
	} else {
		console.error('Error:', result.error)
	}
})

// Example usage: async await:
const main = async () => {
	const result = await doFetch('/api/v1/users', {
		validator: (data: {userName: 'abc'}) => true
	})
	if (result.isSuccess()) {
		console.log('Data:', result.value.userName)
	} else {
		console.error('Error:', result.error)
	}
}
